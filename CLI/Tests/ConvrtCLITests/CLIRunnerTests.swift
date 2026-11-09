import XCTest
import ImageIO
import UniformTypeIdentifiers
@testable import ConvrtCore

final class CLIRunnerTests: XCTestCase {
    private var dir: URL!
    private var out: [String] = []
    private var err: [String] = []
    private let fm = FileManager.default

    override func setUpWithError() throws {
        dir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        out = []; err = []
        CLIIO.out = { [unowned self] in self.out.append($0) }
        CLIIO.err = { [unowned self] in self.err.append($0) }
    }

    override func tearDownWithError() throws {
        try? fm.removeItem(at: dir)
        CLIIO.reset()
    }

    private func png(_ name: String) throws -> URL {
        let ctx = CGContext(data: nil, width: 40, height: 20, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(red: 0, green: 0.4, blue: 1, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: 40, height: 20))
        let url = dir.appendingPathComponent(name)
        let d = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(d, ctx.makeImage()!, nil); CGImageDestinationFinalize(d)
        return url
    }

    func testConvertWritesTheFileAndPrintsItsPath() throws {
        let src = try png("a.png")
        XCTAssertEqual(runCLI(["convert", src.path, "--to", "jpg"]), 0)
        let expected = dir.appendingPathComponent("a.jpg").path
        XCTAssertTrue(fm.fileExists(atPath: expected))
        XCTAssertEqual(out, [expected])
    }

    func testConvertToAnotherFolder() throws {
        let src = try png("a.png"), dest = dir.appendingPathComponent("out")
        try fm.createDirectory(at: dest, withIntermediateDirectories: true)
        XCTAssertEqual(runCLI(["convert", src.path, "--to", "jpg", "--out", dest.path]), 0)
        XCTAssertTrue(fm.fileExists(atPath: dest.appendingPathComponent("a.jpg").path))
        XCTAssertFalse(fm.fileExists(atPath: dir.appendingPathComponent("a.jpg").path))
    }

    func testMissingOutputFolderIsAnErrorNotASilentFallback() throws {
        XCTAssertEqual(runCLI(["convert", try png("a.png").path, "--to", "jpg", "--out", dir.appendingPathComponent("nope").path]), 2)
        XCTAssertTrue(err.joined().contains("nope"))
    }

    func testMissingInputFileFailsButOthersStillConvert() throws {
        let good = try png("good.png")
        let code = runCLI(["convert", dir.appendingPathComponent("ghost.png").path, good.path, "--to", "jpg"])
        XCTAssertEqual(code, 1)
        XCTAssertTrue(fm.fileExists(atPath: dir.appendingPathComponent("good.jpg").path))
        XCTAssertTrue(err.joined().contains("ghost.png"))
    }

    func testOriginalsAreNeverTrashedFromTheCommandLine() throws {
        UserDefaults.standard.set(true, forKey: AppSettings.Key.deleteOriginal)
        defer { UserDefaults.standard.removeObject(forKey: AppSettings.Key.deleteOriginal) }
        let src = try png("keep.png")
        XCTAssertEqual(runCLI(["convert", src.path, "--to", "jpg"]), 0)
        XCTAssertTrue(fm.fileExists(atPath: src.path))
    }

    func testToolRunsAndInfoPrints() throws {
        let src = try png("a.png")
        XCTAssertEqual(runCLI(["tool", "rotate-right", src.path]), 0)
        XCTAssertTrue(fm.fileExists(atPath: dir.appendingPathComponent("a-rotated.png").path))
        out = []
        XCTAssertEqual(runCLI(["tool", "info", src.path]), 0)
        XCTAssertTrue(out.joined(separator: "\n").contains("40 × 20"))
    }

    func testFormatsListsEverythingOrWhatAFileCanBecome() throws {
        XCTAssertEqual(runCLI(["formats"]), 0)
        XCTAssertTrue(out.joined(separator: "\n").contains("jpg"))
        out = []
        XCTAssertEqual(runCLI(["formats", try png("a.png").path]), 0)
        let text = out.joined(separator: "\n")
        XCTAssertTrue(text.contains("jpg") && !text.contains("mp3"), text)
    }

    func testUsageErrorsExitWithTwo() {
        XCTAssertEqual(runCLI(["frobnicate"]), 2)
        XCTAssertEqual(runCLI(["convert", "x.png"]), 2)
        XCTAssertFalse(err.isEmpty)
    }

    func testHelpAndVersionExitZero() {
        XCTAssertEqual(runCLI(["--help"]), 0)
        XCTAssertTrue(out.joined().contains("convert"))
        out = []
        XCTAssertEqual(runCLI(["--version"]), 0)
        XCTAssertTrue(out.joined().contains("convrt"))
    }
}
