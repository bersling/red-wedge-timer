import SwiftUI

struct TimerScreen: View {
    @StateObject private var model = TimerModel()
    @Environment(\.colorScheme) private var scheme
    @Environment(\.scenePhase) private var phase

    private var palette: Palette { Palette.of(scheme) }

    /// Invisible padding that turns each small pill into a real target.
    #if os(iOS)
    private static let hitPadding: CGFloat = 11
    #else
    private static let hitPadding: CGFloat = 8
    #endif

    var body: some View {
        VStack(spacing: 16) {
            header
            DialView(model: model, palette: palette)
                .frame(minHeight: 240, idealHeight: 340)
                .layoutPriority(1)
            readout
            presets
            controls
            footer
        }
        .padding(.horizontal, 22)
        .padding(.top, 16)
        .padding(.bottom, 22)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(palette.paper)
        #if os(iOS)
        .onAppear { model.restore() }
        .onChange(of: phase) { _, now in
            if now == .active { model.catchUp() }
        }
        #endif
    }

    // MARK: - header

    private var header: some View {
        VStack(spacing: 7) {
            // the lengths sit level with the wordmark; the sound gets its own row
            HStack {
                HStack(spacing: 8) {
                    DiskMark(palette: palette)
                        .frame(width: 14, height: 14)
                    #if os(macOS)
                    Text("Red Wedge Timer")
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(palette.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    #endif
                }
                Spacer(minLength: 10)
                beepControl
            }
            HStack {
                Spacer()
                soundMenu
            }
        }
    }

    private var readout: some View {
        VStack(spacing: 2) {
            Text(model.clock)
                .font(.system(size: 46, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(palette.ink)
            Text(model.stateLabel.uppercased())
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .tracking(1.8)
                .foregroundStyle(model.isDone ? palette.wedge : palette.muted)
        }
    }

    // MARK: - picking a length

    private var presets: some View {
        VStack(spacing: 10) {
            Text("HOW LONG?")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .tracking(1.6)
                .foregroundStyle(palette.muted)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 5), spacing: 8) {
                ForEach(TimerModel.presets, id: \.self) { value in
                    let on = model.minutes == value && model.isFresh
                    Button { model.setMinutes(value) } label: {
                        Text("\(value)")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(on ? palette.paper : palette.ink)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: 11, style: .continuous)
                                    .fill(on ? palette.ink : palette.chip)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                                            .strokeBorder(on ? palette.ink : palette.hairline, lineWidth: 1.5)
                                    )
                            )
                    }
                    .buttonStyle(.plain)
                    .help("\(value) minute\(value == 1 ? "" : "s")")
                }
            }
        }
    }

    // MARK: - controls

    private var controls: some View {
        HStack(spacing: 12) {
            stepper(symbol: "minus", delta: -1, enabled: model.minutes > 1)
            Button(action: model.toggle) {
                Text(model.primaryLabel)
                    .font(.system(size: 19, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.97))
                    .frame(minWidth: 150)
                    .padding(.vertical, 15)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(model.isRunning ? palette.teal : palette.wedge)
                            .shadow(color: (model.isRunning ? palette.teal : palette.wedge).opacity(0.45),
                                    radius: 0, y: 5)
                    )
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.space, modifiers: [])
            stepper(symbol: "plus", delta: 1, enabled: model.minutes < TimerModel.maxMinutes)
        }
    }

    private func stepper(symbol: String, delta: Int, enabled: Bool) -> some View {
        Button { model.nudge(delta) } label: {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(enabled ? palette.ink : palette.muted.opacity(0.5))
                .frame(width: 52, height: 52)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(palette.chip)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .strokeBorder(palette.hairline, lineWidth: 1.5)
                        )
                )
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .help(delta > 0 ? "One minute more" : "One minute less")
    }

    private var beepControl: some View {
        HStack(spacing: 9) {
            Image(systemName: model.soundOn ? "speaker.wave.2.fill" : "speaker.slash.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(model.soundOn ? palette.muted : palette.ink)
                .frame(width: 19)
                .help("How long it beeps when the time is up")
            HStack(spacing: 2) {
                ForEach(TimerModel.AlarmLength.allCases) { length in
                    let on = model.alarmLength == length
                    Button { model.setAlarmLength(length) } label: {
                        Text(length.label)
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(on ? .white : palette.muted)
                            .frame(width: 36, height: 23)
                            .background(
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .fill(on ? palette.wedge : Color.clear)
                            )
                            // the click area reaches well past the pill, which
                            // stays small
                            .padding(.vertical, Self.hitPadding)
                            .padding(.horizontal, 4)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(length.help)
                }
            }
            .padding(.vertical, -Self.hitPadding)
            .padding(3)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(palette.chip)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(palette.hairline, lineWidth: 1)
                    )
            )
        }
    }

    private var soundMenu: some View {
        Menu {
            ForEach(AlarmSound.allCases) { choice in
                Button {
                    model.setSound(choice)
                } label: {
                    if choice == model.sound {
                        Label(choice.label, systemImage: "checkmark")
                    } else {
                        Text(choice.label)
                    }
                }
            }
        } label: {
            HStack(spacing: 5) {
                Text(model.sound.label)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
            }
            .foregroundStyle(palette.muted)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule()
                    .fill(palette.chip)
                    .overlay(Capsule().strokeBorder(palette.hairline, lineWidth: 1))
            )
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Which sound plays when the time is up")
    }

    // MARK: - footer

    private var footer: some View {
        VStack(spacing: 10) {
            if model.isAlerting && model.soundOn {
                Button(action: model.silenceAlarm) {
                    Text("Stop the beeping")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(palette.paper)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                        .background(Capsule().fill(palette.ink))
                }
                .buttonStyle(.plain)
            } else {
                Button(action: model.reset) {
                    Text("Back to the start")
                        .font(.system(size: 13, weight: .regular, design: .rounded))
                        .foregroundStyle(palette.muted)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.escape, modifiers: [])
            }
            Text(Self.hint)
                .font(.system(size: 12, design: .rounded))
                .foregroundStyle(palette.muted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
        }
    }
}

extension TimerScreen {
    #if os(iOS)
    static let hint = "Turn the dial to pick any time up to an hour."
    #else
    static let hint = "Turn the dial to pick any time up to an hour. Space starts and pauses."
    #endif
}

/// The little two-tone disk in the wordmark.
struct DiskMark: View {
    let palette: Palette
    var body: some View {
        Circle()
            .fill(palette.rim)
            .overlay(
                GeometryReader { geo in
                    let r = min(geo.size.width, geo.size.height) / 2
                    Path { p in
                        p.move(to: CGPoint(x: r, y: r))
                        p.addArc(center: CGPoint(x: r, y: r), radius: r,
                                 startAngle: .degrees(-90), endAngle: .degrees(180), clockwise: false)
                        p.closeSubpath()
                    }
                    .fill(palette.wedge)
                }
            )
            .clipShape(Circle())
    }
}
