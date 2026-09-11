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
        scheduleNotification()
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
        cancelNotification()
        silenceAlarm()
    }

    /// Called when the app comes back to the front: a suspended app's timer does
    /// not tick, so the end date is the only thing worth trusting.
    func catchUp() {
        guard isRunning, let endsAt else { return }
        remaining = max(0, endsAt.timeIntervalSinceNow)
        if remaining <= 0 { tick() }
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

    private func scheduleNotification() {
        #if os(iOS)
        guard alarmLength != .off, remaining > 0 else { return }
        let content = UNMutableNotificationContent()
        content.title = "Time's up!"
        content.body = "The red disk is gone."
        content.sound = .defaultCritical
        let request = UNNotificationRequest(
            identifier: "redwedge.alarm",
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: remaining, repeats: false)
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
        alarmStartedAt = Date()
        isAlerting = true
        if alarmLength != .off { beeper.alarm(sound) }
        alarmTimer = Timer.scheduledTimer(withTimeInterval: 1.4, repeats: true) { _ in
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
        if alarmLength != .off { beeper.alarm(sound) }
    }

    func silenceAlarm() {
        alarmTimer?.invalidate()
        alarmTimer = nil
        alarmStartedAt = nil
        isAlerting = false
    }

    func setSound(_ choice: AlarmSound) {
        sound = choice
        if alarmLength != .off { beeper.preview(choice) }
    }

    func setAlarmLength(_ length: AlarmLength) {
        alarmLength = length
        if length == .off { silenceAlarm() }
    }
}
