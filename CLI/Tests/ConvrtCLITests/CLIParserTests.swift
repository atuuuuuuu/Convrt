import XCTest
@testable import ConvrtCore

final class CLIParserTests: XCTestCase {
    private func parse(_ args: String...) throws -> Command { try CLIParser.parse(args) }

    func testNoArgumentsMeansHelp() throws { XCTAssertEqual(try CLIParser.parse([]), .help) }
    func testHelpAndVersionFlags() throws {
        XCTAssertEqual(try parse("--help"), .help)
        XCTAssertEqual(try parse("-h"), .help)
        XCTAssertEqual(try parse("--version"), .version)
    }

    func testConvertWithFilesThenTo() throws {
        XCTAssertEqual(try parse("convert", "a.heic", "b.heic", "--to", "jpg"),
                       .convert(files: ["a.heic", "b.heic"], format: .jpg, outputFolder: nil))
    }

    func testConvertAcceptsEqualsFormAndFlagFirst() throws {
        XCTAssertEqual(try parse("convert", "--to=png", "a.jpg"), .convert(files: ["a.jpg"], format: .png, outputFolder: nil))
    }

    func testConvertWithOutputFolderExpandsTilde() throws {
        let c = try parse("convert", "a.wav", "--to", "mp3", "--out", "~/Music/Out")
        XCTAssertEqual(c, .convert(files: ["a.wav"], format: .mp3, outputFolder: NSHomeDirectory() + "/Music/Out"))
    }

    func testFormatNamesAreCaseInsensitiveAndAcceptAliases() throws {
        XCTAssertEqual(try parse("convert", "a.png", "--to", "JPG"), .convert(files: ["a.png"], format: .jpg, outputFolder: nil))
        XCTAssertEqual(try parse("convert", "a.png", "--to", "jpeg"), .convert(files: ["a.png"], format: .jpg, outputFolder: nil))
        XCTAssertEqual(try parse("convert", "a.png", "--to", "tif"), .convert(files: ["a.png"], format: .tiff, outputFolder: nil))
    }

    func testUnknownFormatListsTheValidOnes() {
        XCTAssertThrowsError(try parse("convert", "a.png", "--to", "docx")) {
            let text = $0.localizedDescription
            XCTAssertTrue(text.contains("docx") && text.contains("png") && text.contains("mp3"), text)
        }
    }

    func testConvertNeedsFilesAndTarget() {
        XCTAssertThrowsError(try parse("convert", "--to", "png"))
        XCTAssertThrowsError(try parse("convert", "a.png"))
        XCTAssertThrowsError(try parse("convert", "a.png", "--to"))
    }

    func testToolNames() throws {
        XCTAssertEqual(try parse("tool", "compress", "a.jpg"), .tool(.compress, files: ["a.jpg"], outputFolder: nil))
        XCTAssertEqual(try parse("tool", "strip", "a.jpg"), .tool(.stripMetadata, files: ["a.jpg"], outputFolder: nil))
        XCTAssertEqual(try parse("tool", "rotate-right", "a.jpg"), .tool(.rotateRight, files: ["a.jpg"], outputFolder: nil))
        XCTAssertEqual(try parse("tool", "zip", "a", "b"), .tool(.zip, files: ["a", "b"], outputFolder: nil))
        XCTAssertEqual(try parse("tool", "info", "a.pdf"), .tool(.info, files: ["a.pdf"], outputFolder: nil))
    }

    func testToolTrimTakesStartAndEnd() throws {
        XCTAssertEqual(try parse("tool", "trim", "clip.mov", "--from", "0:05", "--to", "0:20"),
                       .trim(files: ["clip.mov"], start: 5, end: 20, outputFolder: nil))
        XCTAssertThrowsError(try parse("tool", "trim", "clip.mov"))
        XCTAssertThrowsError(try parse("tool", "trim", "clip.mov", "--from", "9", "--to", "2"))
    }

    func testUnknownToolIsExplained() {
        XCTAssertThrowsError(try parse("tool", "explode", "a.jpg")) { XCTAssertTrue($0.localizedDescription.contains("explode")) }
    }

    func testInteractiveToolsAreRefused() {
        XCTAssertThrowsError(try parse("tool", "crop", "a.jpg")) { XCTAssertTrue($0.localizedDescription.lowercased().contains("window")) }
    }

    func testFormatsCommand() throws {
        XCTAssertEqual(try parse("formats"), .formats(file: nil))
        XCTAssertEqual(try parse("formats", "song.mp3"), .formats(file: "song.mp3"))
    }

    func testWatch() throws {
        XCTAssertEqual(try parse("watch", "/tmp/in", "--to", "pdf"), .watch(folder: "/tmp/in", format: .pdf))
        XCTAssertThrowsError(try parse("watch", "/tmp/in"))
    }

    func testUnknownCommandIsExplained() {
        XCTAssertThrowsError(try parse("frobnicate")) { XCTAssertTrue($0.localizedDescription.contains("frobnicate")) }
    }

    func testFilesStartingWithDashAreAcceptedAfterDoubleDash() throws {
        XCTAssertEqual(try parse("convert", "--to", "png", "--", "-odd.jpg"), .convert(files: ["-odd.jpg"], format: .png, outputFolder: nil))
    }
}
