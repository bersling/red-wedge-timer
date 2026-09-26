// The lock-screen and Dynamic Island face of a running timer. AlarmKit shows
// this Live Activity while it counts down; the alert itself is the system's.

import ActivityKit
import AlarmKit
import SwiftUI
import WidgetKit

@main
struct RedWedgeWidgets: WidgetBundle {
    var body: some Widget {
        CountdownActivity()
    }
}

struct CountdownActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: AlarmAttributes<RedWedgeAlarm>.self) { context in
            HStack(spacing: 16) {
                Wedge(state: context.state)
                    .frame(width: 52, height: 52)
                VStack(alignment: .leading, spacing: 2) {
                    Text(context.attributes.presentation.countdown?.title ?? "Red Wedge Timer")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                    Clock(state: context.state)
                        .font(.system(size: 34, weight: .semibold, design: .rounded))
                }
                Spacer()
            }
            .padding(18)
            .activityBackgroundTint(Palette.light.paper)
            .activitySystemActionForegroundColor(Palette.light.ink)
            .foregroundStyle(Palette.light.ink)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Wedge(state: context.state).frame(width: 44, height: 44)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Clock(state: context.state)
                        .font(.system(size: 30, weight: .semibold, design: .rounded))
                }
            } compactLeading: {
                Wedge(state: context.state).frame(width: 18, height: 18)
            } compactTrailing: {
                Clock(state: context.state)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .frame(maxWidth: 52)
            } minimal: {
                Wedge(state: context.state).frame(width: 18, height: 18)
            }
            .keylineTint(Palette.light.wedge)
        }
    }
}

/// The red disk, as a ring the system winds down by itself: a widget cannot
/// redraw every frame, but a timer-driven progress view can.
private struct Wedge: View {
    let state: AlarmPresentationState

    var body: some View {
        switch state.mode {
        case .countdown(let countdown):
            ProgressView(timerInterval: countdown.startDate...countdown.fireDate,
                         countsDown: true, label: { EmptyView() }, currentValueLabel: { EmptyView() })
                .progressViewStyle(.circular)
                .tint(Palette.light.wedge)
        default:
            Circle().fill(Palette.light.wedge)
        }
    }
}

private struct Clock: View {
    let state: AlarmPresentationState

    var body: some View {
        switch state.mode {
        case .countdown(let countdown):
            Text(timerInterval: Date.now...countdown.fireDate, countsDown: true)
                .monospacedDigit()
                .multilineTextAlignment(.trailing)
        default:
            Text("Time's up!")
        }
    }
}
