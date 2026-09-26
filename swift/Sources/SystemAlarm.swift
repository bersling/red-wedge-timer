#if os(iOS)
import AlarmKit
import SwiftUI

/// The timer as a real system alarm, the kind the Clock app sets: it rings on
/// a locked phone, through the silent switch and Focus, even if the app has
/// been killed. The app itself cannot do that — iOS suspends it a few seconds
/// after the screen goes off, and its own beeper with it.
@available(iOS 26.0, *)
enum SystemAlarm {
    /// Schedules an alarm for `endsAt`, asking permission the first time.
    /// Nil when the answer is no, so the caller falls back to a notification.
    static func schedule(at endsAt: Date, sound: AlarmSound) async -> UUID? {
        let manager = AlarmManager.shared
        do {
            if manager.authorizationState == .notDetermined {
                _ = try await manager.requestAuthorization()
            }
            guard manager.authorizationState == .authorized else { return nil }

            let alert: AlarmPresentation.Alert
            if #available(iOS 26.1, *) {
                alert = AlarmPresentation.Alert(title: "Time's up!")
            } else {
                alert = AlarmPresentation.Alert(
                    title: "Time's up!",
                    stopButton: AlarmButton(text: "Stop", textColor: .white, systemImageName: "stop.fill")
                )
            }
            let attributes = AlarmAttributes<RedWedgeAlarm>(
                presentation: AlarmPresentation(
                    alert: alert,
                    countdown: AlarmPresentation.Countdown(title: "Red Wedge Timer")
                ),
                tintColor: Palette.light.wedge
            )
            // measured after the permission prompt, which can take a while
            let seconds = max(1, endsAt.timeIntervalSinceNow)
            let id = UUID()
            _ = try await manager.schedule(id: id, configuration: .timer(
                duration: seconds,
                attributes: attributes,
                sound: .named("\(sound.rawValue).caf")
            ))
            return id
        } catch {
            NSLog("system alarm failed: \(error.localizedDescription)")
            return nil
        }
    }

    /// Counting down or ringing; false once someone has stopped it.
    static func isPending(_ id: UUID) -> Bool {
        ((try? AlarmManager.shared.alarms) ?? []).contains { $0.id == id }
    }

    /// Silences it if it is ringing, and removes it either way.
    static func cancel(_ id: UUID) {
        try? AlarmManager.shared.stop(id: id)
        try? AlarmManager.shared.cancel(id: id)
    }

    /// Calls `changed` whenever the alarm list changes, with the ids still in it.
    static func watch(_ changed: @escaping @MainActor (Set<UUID>) -> Void) -> Task<Void, Never> {
        Task { @MainActor in
            for await alarms in AlarmManager.shared.alarmUpdates {
                changed(Set(alarms.map(\.id)))
            }
        }
    }
}
#endif
