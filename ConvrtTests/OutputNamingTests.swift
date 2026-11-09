import XCTest
@testable import Convrt

final class OutputNamingTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    private func touch(_ name: String) throws {
        try Data().write(to: dir.appendingPathComponent(name))
    }

    func testUniqueURLFreeNameKept() {
        XCTAssertEqual(OutputNaming.uniqueURL(dir: dir, base: "photo", ext: "png").lastPathComponent, "photo.png")
    }

    func testUniqueURLAddsSuffixWhenTaken() throws {
        try touch("photo.png")
        XCTAssertEqual(OutputNaming.uniqueURL(dir: dir, base: "photo", ext: "png").lastPathComponent, "photo-1.png")
    }

    func testUniqueURLSkipsMultipleTaken() throws {
        try touch("photo.png"); try touch("photo-1.png"); try touch("photo-2.png")
        XCTAssertEqual(OutputNaming.uniqueURL(dir: dir, base: "photo", ext: "png").lastPathComponent, "photo-3.png")
    }

    func testUniqueURLHandlesSpacesAndDots() throws {
        try touch("my photo.v2.jpg")
        XCTAssertEqual(OutputNaming.uniqueURL(dir: dir, base: "my photo.v2", ext: "jpg").lastPathComponent, "my photo.v2-1.jpg")
    }

    func testUniqueURLWithoutExtension() throws {
        try touch("notes")
        XCTAssertEqual(OutputNaming.uniqueURL(dir: dir, base: "notes", ext: "").lastPathComponent, "notes-1")
    }

    func testUniqueURLWithSuffixLabel() throws {
        XCTAssertEqual(OutputNaming.uniqueURL(dir: dir, base: "photo", suffix: "-small", ext: "jpg").lastPathComponent, "photo-small.jpg")
        try touch("photo-small.jpg")
        XCTAssertEqual(OutputNaming.uniqueURL(dir: dir, base: "photo", suffix: "-small", ext: "jpg").lastPathComponent, "photo-small-1.jpg")
    }
}
