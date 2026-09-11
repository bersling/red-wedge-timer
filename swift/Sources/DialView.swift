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
            ZStack {
                Circle()
                    .fill(palette.face)
                    .shadow(color: .black.opacity(0.20), radius: side * 0.05, y: side * 0.022)
                Circle()
                    .strokeBorder(palette.rim, lineWidth: side * 0.026)
                Canvas { ctx, size in draw(in: ctx, size: size) }
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

    // MARK: - dial face

    private func draw(in context: GraphicsContext, size: CGSize) {
        let ctx = context
        let side = min(size.width, size.height)
        let center = CGPoint(x: size.width / 2, y: size.height / 2)

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
        let fraction = min(1, max(0, model.remaining / (60 * 60)))
        if fraction > 0.0005 {
            let radius = side * 0.300
            var wedge = Path()
            if fraction >= 0.9995 {
                wedge.addEllipse(in: CGRect(x: center.x - radius, y: center.y - radius,
                                            width: radius * 2, height: radius * 2))
            } else {
                wedge.move(to: center)
                wedge.addArc(center: center, radius: radius,
                             startAngle: .degrees(-90),
                             endAngle: .degrees(-90 + 360 * fraction),
                             clockwise: false)
                wedge.closeSubpath()
            }
            ctx.fill(wedge, with: .color(palette.wedge))
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
