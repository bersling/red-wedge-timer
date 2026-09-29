import SwiftUI
#if os(iOS)
import UserNotifications
#endif

@MainActor
final class TimerModel: ObservableObject {
    static let maxMinutes = 60
    static let presets = [1, 2, 3, 5, 10, 15, 20, 30, 45, 60]

    /// How long the alarm nags once the disk is empty.
    enum AlarmLength: String, CaseIterable, Identifiable {
        case off, oneSecond, tenSeconds, oneMinute, untilStopped

        var id: String { rawValue }

        var label: String {
            switch self {
            case .off: "Off"
            case .oneSecond: "1s"
            case .tenSeconds: "10s"
            case .oneMinute: "1min"
            case .untilStopped: "On"
            }
        }

        var help: String {
            switch self {
            case .off: "Silent"
            case .oneSecond: "Beep once"
            case .tenSeconds: "Beep for ten seconds"
            case .oneMinute: "Beep for a minute"
            case .untilStopped: "Beep until someone stops it"
            }
        }

        /// Seconds of beeping; nil means it keeps going until stopped.
        var seconds: Double? {
            switch self {
            case .off: 0
            case .oneSecond: 1
            case .tenSeconds: 10
            case .oneMinute: 60
            case .untilStopped: nil
            }
        }
    }

    @Published private(set) var minutes = 15
    @Published private(set) var remaining: TimeInterval = 15 * 60
    @Published private(set) var isRunning = false
    @Published private(set) var isDone = false
    /// True while the timer is actively shouting: the pulse and the stop button
    /// both follow this, so neither outlives the alarm.
    @Published private(set) var isAlerting = false
    @Published private(set) var alarmLength: AlarmLength = .untilStopped
    @Published private(set) var sound: AlarmSound = .beeps

    private var endsAt: Date?
    private var alarmStartedAt: Date?
    private var ticker: Timer?
    private var alarmTimer: Timer?
    private var warned = false
    private let beeper = Beeper()
    private static let endsAtKey = "endsAt"
    private static let systemAlarmKey = "systemAlarmID"

    /// The system alarm standing in for the beeper, while one is scheduled or
    /// ringing. Nil means the app has to make the noise itself.
    private var systemAlarmID: UUID? {
        didSet { UserDefaults.standard.set(systemAlarmID?.uuidString, forKey: Self.systemAlarmKey) }
    }
    private var schedulingAlarm: Task<Void, Never>?
    /// The system alarm only stands in while the app is off screen; in front,
    /// the app's own beeper and pulse do the job without the system's badge.
    private var inBackground = false
    private var watchingAlarms: Task<Void, Never>?

    init() {
        #if os(iOS)
        if #available(iOS 26.0, *) {
            systemAlarmID = UserDefaults.standard.string(forKey: Self.systemAlarmKey).flatMap(UUID.init)
            // someone pressed Stop on the lock screen, or in the system banner
            watchingAlarms = SystemAlarm.watch { [weak self] pending in
                guard let self, let id = self.systemAlarmID, !pending.contains(id),
                      !self.isRunning else { return }
                self.systemAlarmID = nil
                self.silenceAlarm()
            }
        }
        #endif
    }

    var duration: TimeInterval { Double(minutes) * 60 }
    var soundOn: Bool { alarmLength != .off }
    var isFresh: Bool { !isRunning && !isDone && remaining >= duration }

    var stateLabel: String {
        if isDone { return "Time's up!" }
        if isRunning { return "counting down" }
        if remaining < duration { return "paused" }
        return minutes == 1 ? "1 minute" : "\(minutes) minutes"
    }

    var clock: String {
        let total = Int(max(0, remaining.rounded(.up)))
        return String(format: "%02d:%02d", total / 60, total % 60)
    }

    var primaryLabel: String {
        if isDone { return "Again" }
        if isRunning { return "Pause" }
        return remaining < duration ? "Keep going" : "Start"
    }

    // MARK: - setting the length

    func setMinutes(_ value: Int) {
        let clamped = max(1, min(Self.maxMinutes, value))
        stop()
        minutes = clamped
        remaining = duration
        isDone = false
        warned = false
    }

    func nudge(_ delta: Int) { setMinutes(minutes + delta) }

    // MARK: - running

    func toggle() {
        isRunning ? pause() : start()
    }

    func start() {
        guard !isRunning else { return }
        silenceAlarm()
        if isDone || remaining <= 0 {
            isDone = false
            warned = false
            remaining = duration
        }
        endsAt = Date().addingTimeInterval(remaining)
        isRunning = true
        rememberEndDate()
        askAlarmPermission()
        ticker = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { _ in
            MainActor.assumeIsolated { self.tick() }
        }
    }

    func pause() {
        guard isRunning else { return }
        remaining = max(0, endsAt?.timeIntervalSinceNow ?? 0)
        stop()
    }

    func reset() {
        stop()
        isDone = false
        warned = false
        remaining = duration
    }

    private func stop() {
        ticker?.invalidate()
        ticker = nil
        isRunning = false
        endsAt = nil
        forgetEndDate()
        cancelAlarm()
        silenceAlarm()
    }

    /// Called when the app comes back to the front: a suspended app's timer does
    /// not tick, so the end date is the only thing worth trusting.
    private func catchUp() {
        guard isRunning, let endsAt else { return }
        remaining = max(0, endsAt.timeIntervalSinceNow)
        if remaining <= 0 { tick() }
    }

    /// Leaving the screen: from here only the system can be trusted to ring.
    func enteredBackground() {
        inBackground = true
        guard isRunning else { return }
        #if os(iOS)
        // a few seconds' grace, so the schedule lands before iOS suspends us
        let grace = UIApplication.shared.beginBackgroundTask(withName: "schedule alarm")
        scheduleAlarm()
        Task {
            await schedulingAlarm?.value
            UIApplication.shared.endBackgroundTask(grace)
        }
        #endif
    }

    /// Back on screen: the app rings for itself again, so the system alarm goes,
    /// unless it is already ringing.
    func enteredForeground() {
        inBackground = false
        catchUp()
        if isRunning { cancelAlarm() }
    }

    // MARK: - surviving suspension

    private func rememberEndDate() {
        UserDefaults.standard.set(endsAt, forKey: Self.endsAtKey)
    }

    private func forgetEndDate() {
        UserDefaults.standard.removeObject(forKey: Self.endsAtKey)
    }

    /// Restores a timer that was running when the app was last closed.
    func restore() {
        guard let saved = UserDefaults.standard.object(forKey: Self.endsAtKey) as? Date else { return }
        let left = saved.timeIntervalSinceNow
        guard left > 0 else {
            forgetEndDate()
            return
        }
        minutes = max(1, min(Self.maxMinutes, Int((left / 60).rounded(.up))))
        remaining = left
        start()
    }

    /// iOS cannot ask for permission from the background, where the alarm gets
    /// scheduled, so Start asks: for alarms, or for notifications without them.
    private func askAlarmPermission() {
        #if os(iOS)
        guard alarmLength != .off else { return }
        Task {
            if #available(iOS 26.0, *), await SystemAlarm.authorize() { return }
            _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
        }
        #endif
    }

    /// Makes sure something rings when the disk empties while the app is off
    /// screen: a system alarm where iOS has them, else a notification.
    private func scheduleAlarm() {
        #if os(iOS)
        guard alarmLength != .off, let endsAt else { return }
        if #available(iOS 26.0, *) {
            let sound = sound
            schedulingAlarm = Task {
                let id = await SystemAlarm.schedule(at: endsAt, sound: sound)
                // a Pause or Reset that landed while we waited wins
                guard !Task.isCancelled, self.endsAt == endsAt else {
                    if let id { SystemAlarm.cancel(id) }
                    return
                }
                if let id {
                    self.systemAlarmID = id
                } else {
                    self.scheduleNotification()
                }
            }
        } else {
            scheduleNotification()
        }
        #endif
    }

    private func cancelAlarm() {
        #if os(iOS)
        schedulingAlarm?.cancel()
        schedulingAlarm = nil
        if #available(iOS 26.0, *), let id = systemAlarmID { SystemAlarm.cancel(id) }
        systemAlarmID = nil
        cancelNotification()
        #endif
    }

    /// Fallback for when there is no system alarm: rings once, and the silent
    /// switch mutes it, but it is better than nothing.
    private func scheduleNotification() {
        #if os(iOS)
        guard let endsAt, endsAt.timeIntervalSinceNow > 0 else { return }
        let content = UNMutableNotificationContent()
        content.title = "Time's up!"
        content.body = "The red disk is gone."
        content.sound = UNNotificationSound(named: UNNotificationSoundName("\(sound.rawValue).caf"))
        let request = UNNotificationRequest(
            identifier: "redwedge.alarm",
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: endsAt.timeIntervalSinceNow, repeats: false)
        )
        let centre = UNUserNotificationCenter.current()
        centre.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            centre.add(request)
        }
        #endif
    }

    private func cancelNotification() {
        #if os(iOS)
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: ["redwedge.alarm"])
        #endif
    }

    private func tick() {
        guard let endsAt else { return }
        remaining = max(0, endsAt.timeIntervalSinceNow)

        if !warned, remaining <= 60, duration > 90 {
            warned = true
            if soundOn { beeper.warn() }
        }

        if remaining <= 0 {
            ticker?.invalidate()
            ticker = nil
            isRunning = false
            self.endsAt = nil
            isDone = true
            beginAlarm()
        }
    }

    // MARK: - the alarm keeps going until somebody stops it

    private func beginAlarm() {
        #if os(iOS)
        if #available(iOS 26.0, *), let id = systemAlarmID {
            // the system rings; the app only pulses, and cuts it short for the
            // shorter lengths. Already stopped on the lock screen: nothing to do.
            guard SystemAlarm.isPending(id) else {
                systemAlarmID = nil
                return
            }
        }
        #endif
        alarmStartedAt = Date()
        isAlerting = true
        if alarmLength != .off, systemAlarmID == nil { beeper.alarm(sound) }
        alarmTimer = Timer.scheduledTimer(withTimeInterval: AlarmSound.repeatEvery, repeats: true) { _ in
            MainActor.assumeIsolated { self.repeatAlarm() }
        }
    }

    private func repeatAlarm() {
        let elapsed = Date().timeIntervalSince(alarmStartedAt ?? Date())
        // silent still gets a short visible alert
        let limit: Double? = alarmLength == .off ? 8 : alarmLength.seconds
        if let limit, elapsed >= limit {
            silenceAlarm()
            return
        }
        if alarmLength != .off, systemAlarmID == nil { beeper.alarm(sound) }
    }

    func silenceAlarm() {
        #if os(iOS)
        if #available(iOS 26.0, *), !isRunning, let id = systemAlarmID {
            SystemAlarm.cancel(id)
            systemAlarmID = nil
        }
        #endif
        alarmTimer?.invalidate()
        alarmTimer = nil
        alarmStartedAt = nil
        isAlerting = false
    }

    func setSound(_ choice: AlarmSound) {
        sound = choice
        if alarmLength != .off { beeper.preview(choice) }
        rescheduleAlarm()
    }

    func setAlarmLength(_ length: AlarmLength) {
        alarmLength = length
        if length == .off { silenceAlarm() }
        if isRunning { askAlarmPermission() }
        rescheduleAlarm()
    }

    /// The system alarm carries its sound, and Off means none at all.
    private func rescheduleAlarm() {
        guard isRunning, inBackground else { return }
        cancelAlarm()
        scheduleAlarm()
    }
}
