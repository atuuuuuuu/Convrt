import XCTest
import ImageIO
import UniformTypeIdentifiers
@testable import Convrt

final class ToolEngineTests: XCTestCase {
    private var dir: URL!
    private let fm = FileManager.default

    override func setUpWithError() throws {
        AppSettings.registerDefaults()
        dir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try? fm.removeItem(at: dir) }

    private func png(_ name: String, _ w: Int = 120, _ h: Int = 60) throws -> URL {
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(red: 0, green: 0.5, blue: 1, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        let url = dir.appendingPathComponent(name)
        let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, ctx.makeImage()!, nil); CGImageDestinationFinalize(dest)
        return url
    }

    func testBatchContinuesPastABadFile() throws {
        let good = try png("good.png")
        let bad = dir.appendingPathComponent("bad.png"); try Data([1, 2, 3]).write(to: bad)
        let s = ToolEngine.run(.rotateRight, urls: [bad, good])
        XCTAssertEqual(s.outputs.map(\.lastPathComponent), ["good-rotated.png"])
        XCTAssertEqual(s.failures.map(\.name), ["bad.png"])
    }

    func testResizeUsesSettingsMaxDimension() throws {
        UserDefaults.standard.set(50, forKey: AppSettings.Key.toolMaxDimension)
        defer { UserDefaults.standard.removeObject(forKey: AppSettings.Key.toolMaxDimension); AppSettings.registerDefaults() }
        let s = ToolEngine.run(.resize, urls: [try png("a.png", 200, 100)])
        let src = CGImageSourceCreateWithURL(try XCTUnwrap(s.outputs.first) as CFURL, nil)!
        let p = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as! [CFString: Any]
        XCTAssertEqual(p[kCGImagePropertyPixelWidth] as? Int, 50)
    }

    func testMergeProducesOneOutputOrAClearFailure() throws {
        let two = ToolEngine.run(.mergePDF, urls: [try png("a.png"), try png("b.png")])
        XCTAssertEqual(two.outputs.count, 1)
        let one = ToolEngine.run(.mergePDF, urls: [try png("c.png")])
        XCTAssertEqual(one.failures.count, 1)
    }

    func testInfoReturnsTextAndNoFiles() throws {
        let s = ToolEngine.run(.info, urls: [try png("a.png")])
        XCTAssertTrue(s.outputs.isEmpty)
        XCTAssertTrue(try XCTUnwrap(s.detail).contains("120 × 60"))
    }

    func testCropIsNotRunByTheEngine() throws {
        // Crop needs its own window; the engine must say so instead of silently doing nothing.
        let s = ToolEngine.run(.crop, urls: [try png("a.png")])
        XCTAssertEqual(s.failures.count, 1)
    }

    func testSettingsDefaults() {
        AppSettings.registerDefaults()
        XCTAssertEqual(AppSettings.toolMaxDimension, 1920)
        XCTAssertEqual(AppSettings.compressQuality, 0.6, accuracy: 0.001)
    }

    func testWheelKeySettingsDefaultOn() {
        AppSettings.registerDefaults()
        XCTAssertTrue(AppSettings.optionCycles)
        XCTAssertTrue(AppSettings.directJumpKeys)
    }

    func testCatalogOffersCropWheelItemForImages() {
        let items = WheelCatalog.items(for: .tools, urls: [URL(fileURLWithPath: "/tmp/a.png")])
        XCTAssertTrue(items.contains { $0.action == .tool(.crop) })
        XCTAssertLessThanOrEqual(items.count, 12)
    }
}
