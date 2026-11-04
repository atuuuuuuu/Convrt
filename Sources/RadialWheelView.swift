import SwiftUI

private let brandOrange = Color(red: 250 / 255, green: 75 / 255, blue: 0)
private let wedgeGray = Color(white: 0.93)

/// One donut slice with a constant-width gap and softly rounded corners.
/// Slice 0 is centered at the top; slices run clockwise.
struct WheelWedge: Shape {
    let index: Int
    let count: Int
    let innerRadius: CGFloat
    let outerRadius: CGFloat
    var gap: CGFloat = 5       // visible gap between wedges, in points
    var corner: CGFloat = 3    // corner rounding, in points (draw with a stroke of 2 * corner)

    func path(in rect: CGRect) -> Path {
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let slice = 2 * Double.pi / Double(max(count, 1))
        let mid = -Double.pi / 2 + Double(index) * slice
        let a0 = mid - slice / 2
        let a1 = mid + slice / 2

        let rOut = outerRadius - corner
        let rIn = innerRadius + corner
        let half = Double(gap / 2 + corner)
        let dOut = asin(min(half / Double(rOut), 1))
        let dIn = asin(min(half / Double(rIn), 1))

        var p = Path()
        p.addArc(center: c, radius: rOut, startAngle: .radians(a0 + dOut), endAngle: .radians(a1 - dOut), clockwise: false)
        p.addArc(center: c, radius: rIn, startAngle: .radians(a1 - dIn), endAngle: .radians(a0 + dIn), clockwise: true)
        p.closeSubpath()
        return p
    }
}

struct RadialWheelView: View {
    @ObservedObject var model: WheelModel

    private var size: CGFloat { WheelMetrics.panelSize }
    private var inner: CGFloat { WheelMetrics.innerRadius }
    private var outer: CGFloat { WheelMetrics.outerRadius }

    var body: some View {
        ZStack {
            if let message = model.message {
                messagePill(message)
            } else {
                wheel
            }
        }
        .frame(width: size, height: size)
        .animation(.easeOut(duration: 0.1), value: model.highlighted)
        .scaleEffect(model.visible ? 1 : 0.82)
        .opacity(model.visible ? 1 : 0)
    }

    // MARK: - Wheel

    private var wheel: some View {
        ZStack {
            // Wedges share ONE soft shadow (a shadow per wedge looked muddy).
            ZStack {
                ForEach(Array(model.formats.enumerated()), id: \.offset) { i, _ in
                    wedge(i)
                }
            }
            .compositingGroup()
            .shadow(color: .black.opacity(0.22), radius: 12, x: 0, y: 5)

            ForEach(Array(model.formats.enumerated()), id: \.offset) { i, format in
                Text(format.label)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundColor(model.highlighted == i ? .white : Color(white: 0.25))
                    .position(labelPosition(index: i))
                    .allowsHitTesting(false)
            }

            // Center label
            ZStack {
                Circle()
                    .fill(Color(white: 0.98))
                    .frame(width: (inner - 10) * 2, height: (inner - 10) * 2)
                    .shadow(color: .black.opacity(0.18), radius: 7, y: 2)
                Text(model.centerText)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundColor(model.highlighted == nil ? Color(white: 0.45) : brandOrange)
                    .multilineTextAlignment(.center)
                    .frame(width: (inner - 16) * 2)
                    .minimumScaleFactor(0.7)
            }
        }
    }

    private func wedge(_ i: Int) -> some View {
        let active = model.highlighted == i
        let color = active ? brandOrange : wedgeGray
        let shape = WheelWedge(index: i, count: model.formats.count, innerRadius: inner, outerRadius: outer)
        return shape
            .fill(color)
            .overlay(shape.stroke(color, style: StrokeStyle(lineWidth: 6, lineJoin: .round)))
    }

    private func labelPosition(index: Int) -> CGPoint {
        let slice = 360.0 / Double(max(model.formats.count, 1))
        let angle = (-90.0 + Double(index) * slice) * .pi / 180
        let r = (inner + outer) / 2
        return CGPoint(x: size / 2 + r * CGFloat(cos(angle)),
                       y: size / 2 + r * CGFloat(sin(angle)))
    }

    // MARK: - "Can't convert" message

    private func messagePill(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 14, weight: .semibold, design: .rounded))
            .foregroundColor(Color(white: 0.25))
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background(Capsule().fill(Color(white: 0.96)))
            .shadow(color: .black.opacity(0.2), radius: 10, y: 4)
    }
}
