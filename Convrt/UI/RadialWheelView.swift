import SwiftUI

private let wedgeFill = Theme.ice

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
        // Clamp so a small inner radius (or many wedges) ends in a point instead of flipping the arc (thanks u/Enlitened).
        let dIn = min(asin(min(half / Double(rIn), 1)), slice / 2)

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
                ForEach(Array(model.items.enumerated()), id: \.offset) { i, _ in
                    wedge(i)
                }
            }
            .compositingGroup()
            .shadow(color: Theme.navy.opacity(0.25), radius: 12, x: 0, y: 5)

            ForEach(Array(model.items.enumerated()), id: \.offset) { i, item in
                itemLabel(item, active: model.highlighted == i)
                    .position(labelPosition(index: i))
                    .allowsHitTesting(false)
            }

            centre
        }
        .animation(.easeOut(duration: 0.15), value: model.kind)
    }

    private var labelWidth: CGFloat {
        let arc = 2 * .pi * (inner + outer) / 2 / CGFloat(max(model.items.count, 1))
        return max(44, min(74, arc - 6))
    }

    private func itemLabel(_ item: WheelItem, active: Bool) -> some View {
        let showIcon = model.kind != .convert
        let crowded = model.items.count > 8
        return VStack(spacing: 2) {
            if showIcon {
                Image(systemName: item.symbol)
                    .font(.system(size: crowded ? 13 : 16, weight: .semibold))
            }
            Text(item.label)
                .font(.system(size: crowded ? 10.5 : (showIcon ? 11.5 : 14), weight: .semibold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .foregroundColor(active ? .white : Theme.navy.opacity(0.85))
        .frame(width: labelWidth)
    }

    private var centre: some View {
        ZStack {
            Circle()
                .fill(Color.white)
                .frame(width: (inner - 10) * 2, height: (inner - 10) * 2)
                .shadow(color: Theme.navy.opacity(0.2), radius: 7, y: 2)
            VStack(spacing: 3) {
                Text(model.kind.title.uppercased())
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .tracking(1)
                    .foregroundColor(Theme.primary.opacity(0.85))
                Text(model.highlightedLabel ?? "Choose")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(model.highlighted == nil ? Theme.navy.opacity(0.5) : Theme.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                HStack(spacing: 4) {
                    ForEach(model.availableKinds, id: \.rawValue) { k in
                        Circle()
                            .fill(k == model.kind ? Theme.primary : Theme.navy.opacity(0.18))
                            .frame(width: 5, height: 5)
                    }
                }
            }
            .multilineTextAlignment(.center)
            .frame(width: (inner - 16) * 2)
        }
    }

    private func wedge(_ i: Int) -> some View {
        let active = model.highlighted == i
        let color = active ? Theme.primary : wedgeFill
        let shape = WheelWedge(index: i, count: model.items.count, innerRadius: inner, outerRadius: outer)
        return shape
            .fill(color)
            .overlay(shape.stroke(color, style: StrokeStyle(lineWidth: 6, lineJoin: .round)))
            .shadow(color: active ? Theme.glow.opacity(0.8) : .clear, radius: 9)
    }

    private func labelPosition(index: Int) -> CGPoint {
        let slice = 360.0 / Double(max(model.items.count, 1))
        let angle = (-90.0 + Double(index) * slice) * .pi / 180
        let r = (inner + outer) / 2
        return CGPoint(x: size / 2 + r * CGFloat(cos(angle)),
                       y: size / 2 + r * CGFloat(sin(angle)))
    }

    // MARK: - Message pill

    private func messagePill(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 14, weight: .semibold, design: .rounded))
            .foregroundColor(Theme.navy.opacity(0.85))
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background(Capsule().fill(Theme.ice))
            .shadow(color: .black.opacity(0.2), radius: 10, y: 4)
    }
}
