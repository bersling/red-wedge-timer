#if os(macOS)
import SwiftUI

@main
struct RedWedgeTimerMacApp: App {
    var body: some Scene {
        WindowGroup("Red Wedge Timer") {
            TimerScreen()
                .frame(minWidth: 390, minHeight: 660)
        }
        .defaultSize(width: 460, height: 780)
        .windowResizability(.contentMinSize)
    }
}
#endif
