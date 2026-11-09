import SwiftUI
import AppKit

final class CropModel: ObservableObject {
    let url: URL
    let image: CGImage
    let position: String            // "2 of 5", empty for a single image
    @Published var geometry: CropGeometry
    @Published var preset: CropGeometry.Preset = .free

    init(url: URL, image: CGImage, position: String) {
        self.url = url
        self.image = image
        self.position = position
        geometry = CropGeometry(bounds: CGSize(width: image.width, height: image.height))
    }

    func apply(_ preset: CropGeometry.Preset) {
        self.preset = preset
        geometry.setAspect(preset.ratio(for: geometry.bounds))
    }
}

/// The interactive cropper: drag the 8 handles or the box, pick an aspect ratio, press Crop.
struct CropEditorView: View {
    @ObservedObject var model: CropModel
    let hasMore: Bool
    let onCrop: () -> Void
    let onSkip: () -> Void
    let onCancel: () -> Void

    @State private var dragBase: CropGeometry?
    @State private var dragHandle: CropGeometry.Handle?

    private typealias Layout = (scale: CGFloat, origin: CGPoint)

    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { proxy in canvas(in: proxy.size) }
                .background(Theme.navy)
            controls
        }
        .frame(minWidth: 640, minHeight: 480)
    }

    // MARK: - Layout (image pixels <-> view points)

    private func layout(_ size: CGSize) -> Layout {
        let img = model.geometry.bounds
        let pad: CGFloat = 28
        let scale = max(0.01, min((size.width - pad * 2) / img.width, (size.height - pad * 2) / img.height))
        return (scale, CGPoint(x: (size.width - img.width * scale) / 2, y: (size.height - img.height * scale) / 2))
    }

    private func viewRect(_ r: CGRect, _ l: Layout) -> CGRect {
        CGRect(x: l.origin.x + r.minX * l.scale, y: l.origin.y + r.minY * l.scale,
               width: r.width * l.scale, height: r.height * l.scale)
    }

    private func handlePoint(_ h: CropGeometry.Handle, in r: CGRect) -> CGPoint? {
        switch h {
        case .topLeft:     return CGPoint(x: r.minX, y: r.minY)
        case .top:         return CGPoint(x: r.midX, y: r.minY)
        case .topRight:    return CGPoint(x: r.maxX, y: r.minY)
        case .right:       return CGPoint(x: r.maxX, y: r.midY)
        case .bottomRight: return CGPoint(x: r.maxX, y: r.maxY)
        case .bottom:      return CGPoint(x: r.midX, y: r.maxY)
        case .bottomLeft:  return CGPoint(x: r.minX, y: r.maxY)
        case .left:        return CGPoint(x: r.minX, y: r.midY)
        case .move:        return nil
        }
    }

    private var resizeHandles: [CropGeometry.Handle] { CropGeometry.Handle.allCases.filter { $0 != .move } }

    private func hit(_ point: CGPoint, in crop: CGRect) -> CropGeometry.Handle? {
        var best: (CropGeometry.Handle, CGFloat)?
        for h in resizeHandles {
            guard let p = handlePoint(h, in: crop) else { continue }
            let d = hypot(p.x - point.x, p.y - point.y)
            if d <= 16, d < (best?.1 ?? .infinity) { best = (h, d) }
        }
        if let best { return best.0 }
        return crop.contains(point) ? .move : nil
    }

    // MARK: - Canvas

    private func canvas(in size: CGSize) -> some View {
        let l = layout(size)
        let imageFrame = viewRect(CGRect(origin: .zero, size: model.geometry.bounds), l)
        let crop = viewRect(model.geometry.rect, l)
        return ZStack(alignment: .topLeading) {
            Image(decorative: model.image, scale: 1)
                .resizable()
                .interpolation(.high)
                .frame(width: imageFrame.width, height: imageFrame.height)
                .position(x: imageFrame.midX, y: imageFrame.midY)

            // Dim everything outside the crop box.
            Path { p in p.addRect(imageFrame); p.addRect(crop) }
                .fill(Color.black.opacity(0.55), style: FillStyle(eoFill: true))

            Rectangle()
                .stroke(Theme.primary, lineWidth: 2)
                .frame(width: crop.width, height: crop.height)
                .position(x: crop.midX, y: crop.midY)

            thirds(in: crop)

            ForEach(resizeHandles, id: \.self) { h in
                if let p = handlePoint(h, in: crop) {
                    Circle()
                        .fill(Color.white)
                        .overlay(Circle().stroke(Theme.primary, lineWidth: 2))
                        .frame(width: 12, height: 12)
                        .position(p)
                }
            }
        }
        .frame(width: size.width, height: size.height)
        .contentShape(Rectangle())
        .gesture(dragGesture(l))
    }

    private func thirds(in r: CGRect) -> some View {
        Path { p in
            for i in 1...2 {
                let x = r.minX + r.width * CGFloat(i) / 3, y = r.minY + r.height * CGFloat(i) / 3
                p.move(to: CGPoint(x: x, y: r.minY)); p.addLine(to: CGPoint(x: x, y: r.maxY))
                p.move(to: CGPoint(x: r.minX, y: y)); p.addLine(to: CGPoint(x: r.maxX, y: y))
            }
        }
        .stroke(Color.white.opacity(0.35), lineWidth: 1)
        .allowsHitTesting(false)
    }

    private func dragGesture(_ l: Layout) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if dragBase == nil {
                    dragBase = model.geometry
                    dragHandle = hit(value.startLocation, in: viewRect(model.geometry.rect, l))
                }
                guard let handle = dragHandle, var g = dragBase else { return }
                g.drag(handle, by: CGSize(width: value.translation.width / l.scale,
                                          height: value.translation.height / l.scale))
                model.geometry = g
            }
            .onEnded { _ in
                dragBase = nil
                dragHandle = nil
            }
    }

    // MARK: - Controls

    private var sizeText: String {
        let r = model.geometry.pixelRect
        return "\(Int(r.width)) × \(Int(r.height)) px"
    }

    private var controls: some View {
        HStack(spacing: 12) {
            Picker("Ratio", selection: Binding(get: { model.preset }, set: { model.apply($0) })) {
                ForEach(CropGeometry.Preset.allCases) { Text($0.title).tag($0) }
            }
            .frame(width: 210)

            Text(sizeText)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .monospacedDigit()
                .foregroundColor(.secondary)

            Button("Reset") { model.geometry.reset() }

            Spacer()

            if !model.position.isEmpty {
                Text(model.position).foregroundColor(.secondary)
            }
            Button("Cancel", action: onCancel).keyboardShortcut(.cancelAction)
            if hasMore { Button("Skip", action: onSkip) }
            Button("Crop", action: onCrop)
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .tint(Theme.primary)
        }
        .padding(12)
        .background(.regularMaterial)
    }
}
