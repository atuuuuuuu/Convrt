import CoreGraphics

/// The crop rectangle and the rules for dragging its handles. Pure maths, no UI.
/// Coordinates are image pixels with the origin at the TOP-left, like `ImageTools.crop`.
struct CropGeometry: Equatable {
    enum Handle: CaseIterable {
        case topLeft, top, topRight, right, bottomRight, bottom, bottomLeft, left, move
    }

    enum Preset: String, CaseIterable, Identifiable {
        case free, original, square, fourThree, sixteenNine, threeTwo, a4Portrait, a4Landscape
        var id: String { rawValue }

        var title: String {
            switch self {
            case .free:         return "Free"
            case .original:     return "Original"
            case .square:       return "1:1 Square"
            case .fourThree:    return "4:3"
            case .sixteenNine:  return "16:9"
            case .threeTwo:     return "3:2"
            case .a4Portrait:   return "A4 Portrait"
            case .a4Landscape:  return "A4 Landscape"
            }
        }

        /// width / height, or nil for free-form.
        func ratio(for size: CGSize) -> CGFloat? {
            switch self {
            case .free:         return nil
            case .original:     return size.height > 0 ? size.width / size.height : nil
            case .square:       return 1
            case .fourThree:    return 4.0 / 3.0
            case .sixteenNine:  return 16.0 / 9.0
            case .threeTwo:     return 3.0 / 2.0
            case .a4Portrait:   return 210.0 / 297.0
            case .a4Landscape:  return 297.0 / 210.0
            }
        }
    }

    static let minSide: CGFloat = 16

    let bounds: CGSize
    private(set) var rect: CGRect
    private(set) var aspect: CGFloat?

    init(bounds: CGSize, aspect: CGFloat? = nil) {
        self.bounds = bounds
        self.rect = CGRect(x: bounds.width / 10, y: bounds.height / 10,
                           width: bounds.width * 8 / 10, height: bounds.height * 8 / 10)
        if let aspect { setAspect(aspect) }
    }

    private var minW: CGFloat { min(Self.minSide, bounds.width) }
    private var minH: CGFloat { min(Self.minSide, bounds.height) }

    /// Whole pixels, always inside the image: what gets cropped.
    var pixelRect: CGRect {
        rect.integral.intersection(CGRect(origin: .zero, size: bounds))
    }

    // MARK: - Aspect

    /// Locks the ratio (width / height) or clears it (nil). Re-fits the rectangle around its centre.
    mutating func setAspect(_ ratio: CGFloat?) {
        aspect = ratio
        guard let a = ratio, a > 0 else { return }
        var w = rect.width, h = w / a
        if h > rect.height { h = rect.height; w = h * a }
        place(width: w, height: h, centre: CGPoint(x: rect.midX, y: rect.midY))
    }

    /// Back to the whole image (or the largest rectangle of the locked ratio that fits).
    mutating func reset() {
        guard let a = aspect else {
            rect = CGRect(origin: .zero, size: bounds)
            return
        }
        var w = bounds.width, h = w / a
        if h > bounds.height { h = bounds.height; w = h * a }
        place(width: w, height: h, centre: CGPoint(x: bounds.width / 2, y: bounds.height / 2))
    }

    private mutating func place(width: CGFloat, height: CGFloat, centre: CGPoint) {
        let x = min(max(centre.x - width / 2, 0), max(bounds.width - width, 0))
        let y = min(max(centre.y - height / 2, 0), max(bounds.height - height, 0))
        rect = CGRect(x: x, y: y, width: width, height: height)
    }

    // MARK: - Dragging

    /// `delta` is how far the handle moved, in image pixels.
    mutating func drag(_ handle: Handle, by delta: CGSize) {
        switch handle {
        case .move:
            let x = min(max(rect.minX + delta.width, 0), bounds.width - rect.width)
            let y = min(max(rect.minY + delta.height, 0), bounds.height - rect.height)
            rect.origin = CGPoint(x: x, y: y)
        case .topLeft, .topRight, .bottomLeft, .bottomRight:
            if let a = aspect { dragCorner(handle, delta, a) } else { dragFree(handle, delta) }
        case .top, .bottom, .left, .right:
            if let a = aspect { dragEdge(handle, delta, a) } else { dragFree(handle, delta) }
        }
    }

    private mutating func dragFree(_ handle: Handle, _ d: CGSize) {
        var x0 = rect.minX, x1 = rect.maxX, y0 = rect.minY, y1 = rect.maxY
        let left: Set<Handle> = [.topLeft, .left, .bottomLeft], right: Set<Handle> = [.topRight, .right, .bottomRight]
        let top: Set<Handle> = [.topLeft, .top, .topRight], bottom: Set<Handle> = [.bottomLeft, .bottom, .bottomRight]
        if left.contains(handle)   { x0 = min(max(x0 + d.width, 0), x1 - minW) }
        if right.contains(handle)  { x1 = max(min(x1 + d.width, bounds.width), x0 + minW) }
        if top.contains(handle)    { y0 = min(max(y0 + d.height, 0), y1 - minH) }
        if bottom.contains(handle) { y1 = max(min(y1 + d.height, bounds.height), y0 + minH) }
        rect = CGRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
    }

    /// The opposite corner stays put; the size follows the pointer but keeps the ratio and the image bounds.
    private mutating func dragCorner(_ handle: Handle, _ d: CGSize, _ a: CGFloat) {
        let sx: CGFloat = (handle == .topLeft || handle == .bottomLeft) ? -1 : 1
        let sy: CGFloat = (handle == .topLeft || handle == .topRight) ? -1 : 1
        let ax = sx > 0 ? rect.minX : rect.maxX
        let ay = sy > 0 ? rect.minY : rect.maxY
        let px = (sx > 0 ? rect.maxX : rect.minX) + d.width
        let py = (sy > 0 ? rect.maxY : rect.minY) + d.height

        let fromW = max(0, sx * (px - ax)), fromH = max(0, sy * (py - ay))
        var w: CGFloat, h: CGFloat
        if fromW / a >= fromH { w = fromW; h = w / a } else { h = fromH; w = h * a }

        let maxW = sx > 0 ? bounds.width - ax : ax
        let maxH = sy > 0 ? bounds.height - ay : ay
        if w > maxW { w = maxW; h = w / a }
        if h > maxH { h = maxH; w = h * a }
        let floorW = max(minW, minH * a)
        if w < floorW { w = floorW; h = w / a }

        rect = CGRect(x: sx > 0 ? ax : ax - w, y: sy > 0 ? ay : ay - h, width: w, height: h)
    }

    /// A side handle changes that side; the other axis follows from the ratio, centred.
    private mutating func dragEdge(_ handle: Handle, _ d: CGSize, _ a: CGFloat) {
        let cx = rect.midX, cy = rect.midY
        var w: CGFloat, h: CGFloat
        switch handle {
        case .left, .right:
            let edge = handle == .right ? rect.maxX + d.width : rect.minX + d.width
            w = handle == .right ? edge - rect.minX : rect.maxX - edge
            w = max(w, max(minW, minH * a))
            let room = handle == .right ? bounds.width - rect.minX : rect.maxX
            let vertical = 2 * min(cy, bounds.height - cy) * a
            w = min(w, room, vertical)
            h = w / a
            let x = handle == .right ? rect.minX : rect.maxX - w
            rect = CGRect(x: x, y: cy - h / 2, width: w, height: h)
        default:
            let edge = handle == .bottom ? rect.maxY + d.height : rect.minY + d.height
            h = handle == .bottom ? edge - rect.minY : rect.maxY - edge
            h = max(h, max(minH, minW / a))
            let room = handle == .bottom ? bounds.height - rect.minY : rect.maxY
            let horizontal = 2 * min(cx, bounds.width - cx) / a
            h = min(h, room, horizontal)
            w = h * a
            let y = handle == .bottom ? rect.minY : rect.maxY - h
            rect = CGRect(x: cx - w / 2, y: y, width: w, height: h)
        }
    }
}
