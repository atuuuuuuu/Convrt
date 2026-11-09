import Foundation
import ImageIO
import CoreImage
import UniformTypeIdentifiers
import Vision

struct ToolError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

/// Image tools. Each takes a file and returns a NEW file next to it (never overwrites, never touches the original).
enum ImageTools {
    // MARK: - Loading and saving

    private struct Loaded {
        let image: CGImage
        let typeID: String
        let properties: [CFString: Any]
    }

    /// Loads the first frame with its EXIF orientation already applied to the pixels.
    private static func load(_ url: URL) throws -> Loaded {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil), CGImageSourceGetCount(source) > 0 else {
            throw ToolError("Couldn’t read this image. It may be corrupt.")
        }
        let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] ?? [:]
        let w = props[kCGImagePropertyPixelWidth] as? Int ?? 0
        let h = props[kCGImagePropertyPixelHeight] as? Int ?? 0
        guard max(w, h) > 0 else { throw ToolError("Couldn’t read this image. It may be corrupt.") }
        let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                        kCGImageSourceCreateThumbnailWithTransform: true,
                                        kCGImageSourceThumbnailMaxPixelSize: max(w, h),
                                        kCGImageSourceShouldCacheImmediately: true]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw ToolError("Couldn’t read this image. It may be corrupt.")
        }
        return Loaded(image: image, typeID: (CGImageSourceGetType(source) as String?) ?? UTType.png.identifier, properties: props)
    }

    private static func save(_ image: CGImage, like loaded: Loaded, from url: URL, suffix: String,
                             keepMetadata: Bool, quality: Double? = nil, forceType: UTType? = nil) throws -> URL {
        var typeID = forceType?.identifier ?? loaded.typeID
        let encodable = (CGImageDestinationCopyTypeIdentifiers() as? [String]) ?? []
        if !encodable.contains(typeID) { typeID = UTType.png.identifier }

        let sameType = typeID == loaded.typeID && forceType == nil
        let ext = sameType && !url.pathExtension.isEmpty
            ? url.pathExtension.lowercased()
            : (UTType(typeID)?.preferredFilenameExtension ?? "png")

        let dir = AppSettings.outputDirectory(for: url)
        guard FileManager.default.isWritableFile(atPath: dir.path) else {
            throw ToolError("No permission to save in “\(dir.lastPathComponent)”.")
        }
        let out = OutputNaming.uniqueURL(dir: dir, base: url.deletingPathExtension().lastPathComponent, suffix: suffix, ext: ext)

        var options: [CFString: Any] = [:]
        if typeID == UTType.jpeg.identifier || typeID == UTType.heic.identifier {
            let q = quality ?? AppSettings.imageQuality
            options[kCGImageDestinationLossyCompressionQuality] = q > 0 ? q : 0.85
        }
        if keepMetadata {
            for key in [kCGImagePropertyExifDictionary, kCGImagePropertyGPSDictionary,
                        kCGImagePropertyIPTCDictionary, kCGImagePropertyTIFFDictionary] {
                if var value = loaded.properties[key] as? [CFString: Any] {
                    if key == kCGImagePropertyTIFFDictionary { value[kCGImagePropertyTIFFOrientation] = 1 }
                    options[key] = value
                }
            }
            options[kCGImagePropertyOrientation] = 1    // pixels are already upright
        }

        guard let dest = CGImageDestinationCreateWithURL(out as CFURL, typeID as CFString, 1, nil) else {
            throw ToolError("Couldn’t create the output file.")
        }
        CGImageDestinationAddImage(dest, image, options as CFDictionary)
        guard CGImageDestinationFinalize(dest) else {
            try? FileManager.default.removeItem(at: out)
            throw ToolError("Couldn’t write the file. Check that the folder is writable.")
        }
        return out
    }

    private static func redraw(_ image: CGImage, width: Int, height: Int, _ draw: (CGContext) -> Void) throws -> CGImage {
        var space = image.colorSpace
        if space?.model != .rgb { space = CGColorSpace(name: CGColorSpace.sRGB) }
        guard let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: space ?? CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              true else { throw ToolError("Not enough memory to edit this image.") }
        ctx.interpolationQuality = .high
        draw(ctx)
        guard let result = ctx.makeImage() else { throw ToolError("Couldn’t edit this image.") }
        return result
    }

    /// The first frame, upright, for showing in the cropper. Its pixel size is the crop coordinate space.
    static func loadForDisplay(_ url: URL) throws -> CGImage { try load(url).image }

    // MARK: - Tools

    static func compress(_ url: URL, quality: Double) throws -> URL {
        let l = try load(url)
        return try save(l.image, like: l, from: url, suffix: "-compressed", keepMetadata: true, quality: quality)
    }

    static func resize(_ url: URL, maxDimension: Int) throws -> URL {
        let l = try load(url)
        let w = l.image.width, h = l.image.height
        var result = l.image
        if max(w, h) > maxDimension, maxDimension > 0 {
            let scale = Double(maxDimension) / Double(max(w, h))
            let nw = max(1, Int((Double(w) * scale).rounded())), nh = max(1, Int((Double(h) * scale).rounded()))
            result = try redraw(l.image, width: nw, height: nh) { $0.draw(l.image, in: CGRect(x: 0, y: 0, width: nw, height: nh)) }
        }
        return try save(result, like: l, from: url, suffix: "-resized", keepMetadata: true)
    }

    static func stripMetadata(_ url: URL) throws -> URL {
        let l = try load(url)
        return try save(l.image, like: l, from: url, suffix: "-clean", keepMetadata: false)
    }

    /// Positive turns are clockwise.
    static func rotate(_ url: URL, quarterTurnsClockwise turns: Int) throws -> URL {
        let l = try load(url)
        let w = l.image.width, h = l.image.height
        let n = ((turns % 4) + 4) % 4
        let result: CGImage
        switch n {
        case 1:
            result = try redraw(l.image, width: h, height: w) {
                $0.translateBy(x: 0, y: CGFloat(w)); $0.rotate(by: -.pi / 2)
                $0.draw(l.image, in: CGRect(x: 0, y: 0, width: w, height: h))
            }
        case 3:
            result = try redraw(l.image, width: h, height: w) {
                $0.translateBy(x: CGFloat(h), y: 0); $0.rotate(by: .pi / 2)
                $0.draw(l.image, in: CGRect(x: 0, y: 0, width: w, height: h))
            }
        case 2:
            result = try redraw(l.image, width: w, height: h) {
                $0.translateBy(x: CGFloat(w), y: CGFloat(h)); $0.rotate(by: .pi)
                $0.draw(l.image, in: CGRect(x: 0, y: 0, width: w, height: h))
            }
        default:
            result = l.image
        }
        return try save(result, like: l, from: url, suffix: "-rotated", keepMetadata: true)
    }

    static func flip(_ url: URL, horizontal: Bool) throws -> URL {
        let l = try load(url)
        let w = l.image.width, h = l.image.height
        let result = try redraw(l.image, width: w, height: h) {
            if horizontal { $0.translateBy(x: CGFloat(w), y: 0); $0.scaleBy(x: -1, y: 1) }
            else { $0.translateBy(x: 0, y: CGFloat(h)); $0.scaleBy(x: 1, y: -1) }
            $0.draw(l.image, in: CGRect(x: 0, y: 0, width: w, height: h))
        }
        return try save(result, like: l, from: url, suffix: "-flipped", keepMetadata: true)
    }

    /// `rect` is in pixels with the origin at the TOP-left, and is clamped to the image.
    static func crop(_ url: URL, to rect: CGRect, suffix: String = "-cropped") throws -> URL {
        let l = try load(url)
        let bounds = CGRect(x: 0, y: 0, width: l.image.width, height: l.image.height)
        let r = rect.integral.intersection(bounds)
        guard !r.isNull, r.width >= 1, r.height >= 1, let cropped = l.image.cropping(to: r) else {
            throw ToolError("The crop area is outside the image.")
        }
        return try save(cropped, like: l, from: url, suffix: suffix, keepMetadata: true)
    }

    static func cropSquare(_ url: URL) throws -> URL {
        let l = try load(url)
        let side = min(l.image.width, l.image.height)
        let rect = CGRect(x: (l.image.width - side) / 2, y: (l.image.height - side) / 2, width: side, height: side)
        return try crop(url, to: rect, suffix: "-square")
    }

    static func mergeToPDF(_ urls: [URL]) throws -> URL {
        guard urls.count >= 2 else { throw ToolError("Pick at least two images to merge.") }
        return try Converter.combineImagesToPDF(urls)
    }

    // MARK: - Background removal (Apple Vision, offline)

    static func removeBackground(_ url: URL) throws -> URL {
        let l = try load(url)
        let ci = CIImage(cgImage: l.image)
        let mask = try subjectMask(for: l.image)
        guard let blend = CIFilter(name: "CIBlendWithMask") else { throw ToolError("Background removal isn’t available on this Mac.") }
        blend.setValue(ci, forKey: kCIInputImageKey)
        blend.setValue(CIImage(color: .clear).cropped(to: ci.extent), forKey: kCIInputBackgroundImageKey)
        blend.setValue(mask, forKey: kCIInputMaskImageKey)
        guard let output = blend.outputImage, let cg = CIContext().createCGImage(output, from: ci.extent) else {
            throw ToolError("Couldn’t remove the background from this image.")
        }
        return try save(cg, like: l, from: url, suffix: "-cutout", keepMetadata: false, forceType: .png)
    }

    private static func subjectMask(for image: CGImage) throws -> CIImage {
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do {
            if #available(macOS 14.0, *) {
                let request = VNGenerateForegroundInstanceMaskRequest()
                try handler.perform([request])
                if let observation = request.results?.first, !observation.allInstances.isEmpty {
                    let buffer = try observation.generateScaledMaskForImage(forInstances: observation.allInstances, from: handler)
                    return CIImage(cvPixelBuffer: buffer)
                }
            }
            let request = VNGeneratePersonSegmentationRequest()
            request.qualityLevel = .accurate
            request.outputPixelFormat = kCVPixelFormatType_OneComponent8
            try handler.perform([request])
            guard let observation = request.results?.first, coverage(of: observation.pixelBuffer) > 0.005 else {
                throw ToolError("No subject found in this image. Background removal works best on photos of people.")
            }
            let mask = CIImage(cvPixelBuffer: observation.pixelBuffer)
            let sx = CGFloat(image.width) / mask.extent.width, sy = CGFloat(image.height) / mask.extent.height
            return mask.transformed(by: CGAffineTransform(scaleX: sx, y: sy))
        } catch let error as ToolError {
            throw error
        } catch {
            throw ToolError("Background removal isn’t available on this Mac (\(error.localizedDescription)).")
        }
    }

    /// Fraction of the mask that is mostly "subject".
    private static func coverage(of buffer: CVPixelBuffer) -> Double {
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return 0 }
        let w = CVPixelBufferGetWidth(buffer), h = CVPixelBufferGetHeight(buffer), stride = CVPixelBufferGetBytesPerRow(buffer)
        guard w > 0, h > 0 else { return 0 }
        var on = 0
        for y in 0..<h {
            let row = base.advanced(by: y * stride).assumingMemoryBound(to: UInt8.self)
            for x in 0..<w where row[x] > 127 { on += 1 }
        }
        return Double(on) / Double(w * h)
    }
}
