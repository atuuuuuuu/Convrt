import XCTest
import ImageIO
import UniformTypeIdentifiers
import PDFKit
@testable import Convrt

final class ImageToolsTests: XCTestCase {
    private var dir: URL!
    private let fm = FileManager.default

    override func setUpWithError() throws {
        dir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try? fm.removeItem(at: dir) }

    // MARK: - Fixtures

    /// Left half red, right half blue.
    private func makeImage(_ w: Int, _ h: Int) -> CGImage {
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: w / 2, height: h))
        ctx.setFillColor(CGColor(red: 0, green: 0, blue: 1, alpha: 1)); ctx.fill(CGRect(x: w / 2, y: 0, width: w - w / 2, height: h))
        return ctx.makeImage()!
    }

    private func noisyImage(_ w: Int, _ h: Int) -> CGImage {
        var bytes = [UInt8](repeating: 0, count: w * h * 4)
        for i in 0..<bytes.count { bytes[i] = i % 4 == 3 ? 255 : UInt8.random(in: 0...255) }
        let provider = CGDataProvider(data: Data(bytes) as CFData)!
        return CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: w * 4,
                       space: CGColorSpace(name: CGColorSpace.sRGB)!,
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
    }

    @discardableResult
    private func save(_ image: CGImage, _ name: String, type: UTType = .png, properties: [CFString: Any] = [:]) throws -> URL {
        let url = dir.appendingPathComponent(name)
        let dest = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, image, properties as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(dest))
        return url
    }

    private func load(_ url: URL) throws -> CGImage {
        let src = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
        return try XCTUnwrap(CGImageSourceCreateImageAtIndex(src, 0, nil))
    }

    private func pixel(_ image: CGImage, _ x: Int, _ y: Int) -> (r: UInt8, g: UInt8, b: UInt8) {
        var px = [UInt8](repeating: 0, count: 4)
        let ctx = CGContext(data: &px, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(image, in: CGRect(x: -x, y: -(image.height - 1 - y), width: image.width, height: image.height))
        return (px[0], px[1], px[2])
    }

    private func properties(_ url: URL) -> [CFString: Any] {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return [:] }
        return CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any] ?? [:]
    }

    // MARK: - Resize / crop / rotate / flip

    func testResizeKeepsAspect() throws {
        let out = try ImageTools.resize(try save(makeImage(400, 200), "a.png"), maxDimension: 100)
        let img = try load(out)
        XCTAssertEqual(img.width, 100); XCTAssertEqual(img.height, 50)
        XCTAssertEqual(out.lastPathComponent, "a-resized.png")
    }

    func testResizeNeverUpscales() throws {
        let img = try load(try ImageTools.resize(try save(makeImage(400, 200), "a.png"), maxDimension: 1000))
        XCTAssertEqual(img.width, 400); XCTAssertEqual(img.height, 200)
    }

    func testCropSquareGives200x200() throws {
        let img = try load(try ImageTools.cropSquare(try save(makeImage(400, 200), "a.png")))
        XCTAssertEqual(img.width, 200); XCTAssertEqual(img.height, 200)
    }

    func testCropToRectUsesTopLeftPixelOrigin() throws {
        let out = try ImageTools.crop(try save(makeImage(400, 200), "a.png"), to: CGRect(x: 250, y: 0, width: 100, height: 50))
        let img = try load(out)
        XCTAssertEqual(img.width, 100); XCTAssertEqual(img.height, 50)
        XCTAssertEqual(pixel(img, 50, 25).b, 255, "right half is blue")
    }

    func testCropRectIsClampedToTheImage() throws {
        let img = try load(try ImageTools.crop(try save(makeImage(400, 200), "a.png"), to: CGRect(x: 350, y: 150, width: 500, height: 500)))
        XCTAssertEqual(img.width, 50); XCTAssertEqual(img.height, 50)
    }

    func testCropOutsideTheImageThrows() throws {
        XCTAssertThrowsError(try ImageTools.crop(try save(makeImage(400, 200), "a.png"), to: CGRect(x: 900, y: 900, width: 10, height: 10)))
    }

    func testRotateSwapsDimensions() throws {
        let src = try save(makeImage(400, 200), "a.png")
        let right = try load(try ImageTools.rotate(src, quarterTurnsClockwise: 1))
        XCTAssertEqual(right.width, 200); XCTAssertEqual(right.height, 400)
        let left = try load(try ImageTools.rotate(src, quarterTurnsClockwise: -1))
        XCTAssertEqual(left.width, 200); XCTAssertEqual(left.height, 400)
    }

    func testRotateClockwiseMovesLeftSideToTop() throws {
        // Red is the left half. Rotated clockwise, the left half becomes the top half.
        let img = try load(try ImageTools.rotate(try save(makeImage(400, 200), "a.png"), quarterTurnsClockwise: 1))
        XCTAssertEqual(pixel(img, 100, 50).r, 255)
        XCTAssertEqual(pixel(img, 100, 350).b, 255)
    }

    func testFlipHorizontalMirrorsPixels() throws {
        let img = try load(try ImageTools.flip(try save(makeImage(400, 200), "a.png"), horizontal: true))
        XCTAssertEqual(pixel(img, 10, 100).b, 255, "left side is now blue")
        XCTAssertEqual(pixel(img, 390, 100).r, 255, "right side is now red")
    }

    // MARK: - Metadata and compression

    func testStripMetadataRemovesGPSAndExif() throws {
        let props: [CFString: Any] = [
            kCGImagePropertyGPSDictionary: [kCGImagePropertyGPSLatitude: 47.9, kCGImagePropertyGPSLongitude: 106.9],
            kCGImagePropertyExifDictionary: [kCGImagePropertyExifUserComment: "secret"]
        ]
        let src = try save(makeImage(64, 64), "geo.jpg", type: .jpeg, properties: props)
        XCTAssertNotNil(properties(src)[kCGImagePropertyGPSDictionary], "fixture must carry GPS")
        let out = try ImageTools.stripMetadata(src)
        XCTAssertNil(properties(out)[kCGImagePropertyGPSDictionary])
        XCTAssertNil((properties(out)[kCGImagePropertyExifDictionary] as? [CFString: Any])?[kCGImagePropertyExifUserComment])
        XCTAssertEqual(out.lastPathComponent, "geo-clean.jpg")
    }

    func testCompressMakesJPEGSmaller() throws {
        let src = try save(noisyImage(500, 500), "n.jpg", type: .jpeg, properties: [kCGImageDestinationLossyCompressionQuality: 0.98])
        let out = try ImageTools.compress(src, quality: 0.4)
        let a = try fm.attributesOfItem(atPath: src.path)[.size] as! Int
        let b = try fm.attributesOfItem(atPath: out.path)[.size] as! Int
        XCTAssertLessThan(b, a)
        XCTAssertEqual(out.pathExtension, "jpg")
    }

    func testOutputNeverOverwrites() throws {
        let src = try save(makeImage(400, 200), "a.png")
        let first = try ImageTools.resize(src, maxDimension: 100), second = try ImageTools.resize(src, maxDimension: 100)
        XCTAssertNotEqual(first, second)
        XCTAssertEqual(second.lastPathComponent, "a-resized-1.png")
    }

    // MARK: - Bad input

    func testCorruptImageThrows() throws {
        let bad = dir.appendingPathComponent("bad.png")
        try Data((0..<300).map { _ in UInt8.random(in: 0...255) }).write(to: bad)
        XCTAssertThrowsError(try ImageTools.resize(bad, maxDimension: 100))
    }

    func testZeroByteFileThrows() throws {
        let empty = dir.appendingPathComponent("empty.jpg")
        fm.createFile(atPath: empty.path, contents: Data())
        XCTAssertThrowsError(try ImageTools.compress(empty, quality: 0.5))
    }

    // MARK: - Merge, info, background

    func testMergeNeedsTwoImages() throws {
        XCTAssertThrowsError(try ImageTools.mergeToPDF([try save(makeImage(50, 50), "a.png")]))
    }

    func testMergeBuildsOnePagePerImage() throws {
        let urls = try (0..<3).map { try save(makeImage(80, 60), "p\($0).png") }
        let pdf = try ImageTools.mergeToPDF(urls)
        XCTAssertEqual(pdf.pathExtension, "pdf")
        XCTAssertEqual(PDFDocument(url: pdf)?.pageCount, 3)
    }

    func testRemoveBackgroundWithNoSubjectReportsIt() throws {
        let src = try save(makeImage(200, 200), "flat.png")
        XCTAssertThrowsError(try ImageTools.removeBackground(src)) { error in
            XCTAssertTrue(error.localizedDescription.lowercased().contains("subject"), error.localizedDescription)
        }
    }
}

final class FileInfoTests: XCTestCase {
    func testImageInfoShowsDimensionsAndSize() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let ctx = CGContext(data: nil, width: 400, height: 200, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let url = dir.appendingPathComponent("pic.png")
        let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, ctx.makeImage()!, nil); CGImageDestinationFinalize(dest)
        let text = FileInfo.describe(url)
        XCTAssertTrue(text.contains("pic.png"))
        XCTAssertTrue(text.contains("400 × 200"), text)
    }

    func testFolderInfoCountsItems() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("sub"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try "a".write(to: dir.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        try "b".write(to: dir.appendingPathComponent("sub/b.txt"), atomically: true, encoding: .utf8)
        let text = FileInfo.describe(dir)
        XCTAssertTrue(text.contains("2 files"), text)
        XCTAssertTrue(text.contains("1 folder"), text)
    }

    func testMissingFileInfoDoesNotCrash() {
        XCTAssertFalse(FileInfo.describe(URL(fileURLWithPath: "/tmp/definitely-missing-\(UUID().uuidString)")).isEmpty)
    }
}
