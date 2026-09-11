#if os(iOS)
import SwiftUI

@main
struct RedWedgeTimerPhoneApp: App {
    var body: some Scene {
        WindowGroup {
            TimerScreen()
        }
    }
}
#endif
