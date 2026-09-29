import SwiftUI
#if os(macOS)
import AppKit
#endif

struct DialView: View {
    @ObservedObject var model: TimerModel
    let palette: Palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            let dial = side / Self.reach
            ZStack {
                Circle()
                    .fill(palette.face)
                    .shadow(color: .black.opacity(0.20), radius: dial * 0.05, y: dial * 0.022)
                    .frame(width: dial, height: dial)
                Circle()
                    .strokeBorder(palette.rim, lineWidth: dial * 0.026)
                    .frame(width: dial, height: dial)
                // spans the halo too, so the knob can stand proud of the rim
                Canvas { ctx, size in draw(in: ctx, size: size, dial: dial) }
            }
            .frame(width: side, height: side)
            .scaleEffect(pulse ? 1.035 : 1.0)
            .onChange(of: model.isAlerting) { _, alerting in
                guard !reduceMotion else { return }
                // an explicit transaction each way: a repeatForever animation
                // left in place is what kept the dial breathing forever
                if alerting {
                    withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) {
                        pulse = true
                    }
                } else {
                    withAnimation(.easeOut(duration: 0.25)) { pulse = false }
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .contentShape(Circle())
            #if os(macOS)
            .onHover { inside in
                if inside { NSCursor.openHand.push() } else { NSCursor.pop() }
            }
            #endif
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
                        model.setMinutes(minutes(at: value.location, center: center))
                    }
            )
            .accessibilityLabel("Minutes on the timer")
            .accessibilityValue("\(model.clock) left")
        }
    }

    /// How far the view reaches past the dial's rim, as a multiple of its
    /// diameter: room for the knob to protrude, and a ring of extra touch area.
    private static let reach: CGFloat = 1.1

    // MARK: - dial face

    private func draw(in context: GraphicsContext, size: CGSize, dial side: CGFloat) {
        let ctx = context
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let fraction = min(1, max(0, model.remaining / (60 * 60)))
        let edge = 360 * fraction  // clockwise from twelve

        // a faint copy of the wedge runs out to the rim, behind ticks and numerals
        if fraction > 0.0005 {
            ctx.fill(sector(fraction, radius: side * 0.474, center),
                     with: .color(palette.wedgeSoft))
        }

        // minute ticks, every fifth one longer
        for minute in 0..<60 {
            let major = minute % 5 == 0
            let angle = Double(minute) * 6
            var path = Path()
            path.move(to: point(angle, side * (major ? 0.424 : 0.434), center))
            path.addLine(to: point(angle, side * 0.460, center))
            ctx.stroke(
                path,
                with: .color(major ? palette.muted : palette.hairline),
                style: StrokeStyle(lineWidth: side * (major ? 0.008 : 0.004), lineCap: .round)
            )
        }

        // the red disk: shrinks clockwise, so its edge points at the minutes left
        if fraction > 0.0005 {
            ctx.fill(sector(fraction, radius: side * 0.300, center), with: .color(palette.wedge))
        }

        // numerals sit outside the disk so the red never covers them
        for value in stride(from: 5, through: 60, by: 5) {
            let quarter = value % 15 == 0
            let angle = Double(value == 60 ? 0 : value) * 6
            let text = Text("\(value)")
                .font(.system(size: side * (quarter ? 0.076 : 0.065),
                              weight: quarter ? .heavy : .semibold,
                              design: .rounded))
                .foregroundStyle(quarter ? palette.ink : palette.muted)
            ctx.draw(ctx.resolve(text), at: point(angle, side * 0.380, center), anchor: .center)
        }

        let hub = side * 0.020
        let hubRect = CGRect(x: center.x - hub, y: center.y - hub, width: hub * 2, height: hub * 2)
        ctx.fill(Path(ellipseIn: hubRect), with: .color(palette.face))
        ctx.stroke(Path(ellipseIn: hubRect), with: .color(palette.rim), lineWidth: side * 0.006)

        // the knob rides the rim at the wedge's edge: something to take hold of,
        // though a drag anywhere on the dial still sets the time
        let knob = side * 0.048
        let at = point(edge, side * 0.487, center)
        let knobRect = CGRect(x: at.x - knob, y: at.y - knob, width: knob * 2, height: knob * 2)
        ctx.drawLayer { layer in
            layer.addFilter(.shadow(color: .black.opacity(0.25), radius: side * 0.012, y: side * 0.006))
            layer.fill(Path(ellipseIn: knobRect), with: .color(palette.wedge))
        }
        ctx.stroke(Path(ellipseIn: knobRect.insetBy(dx: side * 0.005, dy: side * 0.005)),
                   with: .color(palette.face), lineWidth: side * 0.010)
    }

    private func sector(_ fraction: Double, radius: CGFloat, _ center: CGPoint) -> Path {
        var path = Path()
        if fraction >= 0.9995 {
            path.addEllipse(in: CGRect(x: center.x - radius, y: center.y - radius,
                                       width: radius * 2, height: radius * 2))
        } else {
            path.move(to: center)
            path.addArc(center: center, radius: radius,
                        startAngle: .degrees(-90),
                        endAngle: .degrees(-90 + 360 * fraction),
                        clockwise: false)
            path.closeSubpath()
        }
        return path
    }

    // MARK: - geometry

    private func point(_ degrees: Double, _ radius: CGFloat, _ center: CGPoint) -> CGPoint {
        let radians = (degrees - 90) * .pi / 180
        return CGPoint(x: center.x + radius * cos(radians), y: center.y + radius * sin(radians))
    }

    private func minutes(at location: CGPoint, center: CGPoint) -> Int {
        let dx = location.x - center.x
        let dy = location.y - center.y
        var degrees = atan2(dx, -dy) * 180 / .pi
        if degrees < 0 { degrees += 360 }
        let stepped = Int((degrees / 6).rounded())
        if stepped < 1 { return degrees > 180 ? 60 : 1 }
        return stepped
    }
}
