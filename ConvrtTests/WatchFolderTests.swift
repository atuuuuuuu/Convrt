import XCTest
@testable import Convrt

final class WatchFilterTests: XCTestCase {
    func testIgnoresPartialDownloadsAndHiddenFiles() {
        for name in [".DS_Store", ".hidden.png", "movie.crdownload", "a.download", "a.part", "a.tmp", "a.partial",
                     "~$report.docx", "a.png.crdownload", "Untitled.opdownload", ".com.google.Chrome.abc123"] {
            XCTAssertTrue(WatchFilter.shouldIgnore(name: name), name)
        }
    }

    func testKeepsNormalFiles() {
        for name in ["photo.heic", "My Song.mp3", "report.final.pdf", "x"] {
            XCTAssertFalse(WatchFilter.shouldIgnore(name: name), name)
        }
    }
}

final class SettleTrackerTests: XCTestCase {
    private let a = URL(fileURLWithPath: "/w/a.png")
    private let b = URL(fileURLWithPath: "/w/b.png")
    private func stamp(_ size: Int, _ t: TimeInterval = 0) -> FileStamp { FileStamp(size: size, modified: Date(timeIntervalSince1970: t)) }

    func testReportedOnlyAfterTwoIdenticalObservations() {
        var t = SettleTracker()
        XCTAssertEqual(t.observe([a: stamp(10)]), [])
        XCTAssertEqual(t.observe([a: stamp(10)]), [a])
    }

    func testGrowingFileKeepsWaiting() {
        var t = SettleTracker()
        _ = t.observe([a: stamp(10)])
        XCTAssertEqual(t.observe([a: stamp(20)]), [], "size changed, still being written")
        XCTAssertEqual(t.observe([a: stamp(20)]), [a])
    }

    func testModifiedTimeChangeAlsoResets() {
        var t = SettleTracker()
        _ = t.observe([a: stamp(10, 1)])
        XCTAssertEqual(t.observe([a: stamp(10, 2)]), [])
    }

    func testReportedOnlyOnce() {
        var t = SettleTracker()
        _ = t.observe([a: stamp(10)]); _ = t.observe([a: stamp(10)])
        XCTAssertEqual(t.observe([a: stamp(10)]), [])
    }

    func testSeededFilesAreNeverReported() {
        var t = SettleTracker()
        t.seed([a])
        _ = t.observe([a: stamp(10)])
        XCTAssertEqual(t.observe([a: stamp(10)]), [])
    }

    func testIgnoredOutputsAreNeverReported() {
        var t = SettleTracker()
        t.ignore([b])
        _ = t.observe([b: stamp(5)])
        XCTAssertEqual(t.observe([b: stamp(5)]), [])
    }

    func testTwoFilesSettleIndependently() {
        var t = SettleTracker()
        _ = t.observe([a: stamp(1)])
        XCTAssertEqual(t.observe([a: stamp(1), b: stamp(2)]), [a])
        XCTAssertEqual(t.observe([a: stamp(1), b: stamp(2)]), [b])
    }

    func testAFileThatLeavesAndComesBackIsProcessedAgain() {
        var t = SettleTracker()
        _ = t.observe([a: stamp(10)]); _ = t.observe([a: stamp(10)])
        _ = t.observe([:])
        _ = t.observe([a: stamp(10)])
        XCTAssertEqual(t.observe([a: stamp(10)]), [a])
    }
}

final class WatchFolderServiceTests: XCTestCase {
    private var dir: URL!
    private let fm = FileManager.default

    override func setUpWithError() throws {
        dir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try? fm.removeItem(at: dir) }

    private func png(_ name: String, bytes: Int = 8) throws {
        try Data(repeating: 1, count: bytes).write(to: dir.appendingPathComponent(name))
    }

    private func rule(_ format: OutputFormat = .jpg, enabled: Bool = true) -> WatchRule {
        WatchRule(folder: dir.path, format: format.rawValue, enabled: enabled)
    }

    private final class Recorder {
        var calls: [(URL, OutputFormat)] = []
        let queue = DispatchQueue(label: "rec")
        func add(_ u: URL, _ f: OutputFormat) { queue.sync { calls.append((u, f)) } }
        var count: Int { queue.sync { calls.count } }
    }

    private func service(_ rec: Recorder, writeOutput: Bool = false, onResult: ((ConversionSummary) -> Void)? = nil) -> WatchFolderService {
        WatchFolderService(interval: 3600, convert: { [dir] url, format in
            rec.add(url, format)
            var s = ConversionSummary()
            if writeOutput {
                let out = dir!.appendingPathComponent(url.deletingPathExtension().lastPathComponent + ".jpg")
                try? Data(repeating: 2, count: 4).write(to: out)
                s.outputs = [out]
            }
            return s
        }, onResult: { summary, _ in onResult?(summary) })
    }

    private func settle(_ s: WatchFolderService) { s.tick(); s.tick() }

    private func drain(_ s: WatchFolderService) {
        let e = expectation(description: "queue drained")
        s.waitUntilIdle { e.fulfill() }
        wait(for: [e], timeout: 5)
    }

    func testNewFileIsConvertedOnceAfterItSettles() throws {
        try png("old.png")
        let rec = Recorder(), s = service(rec)
        s.apply(rules: [rule()])
        try png("new.png")
        s.tick(); drain(s)
        XCTAssertEqual(rec.count, 0, "still might be growing")
        s.tick(); drain(s)
        XCTAssertEqual(rec.calls.map { $0.0.lastPathComponent }, ["new.png"])
        XCTAssertEqual(rec.calls.first?.1, .jpg)
        s.tick(); s.tick(); drain(s)
        XCTAssertEqual(rec.count, 1, "never twice")
    }

    func testFilesAlreadyThereWhenWatchingStartsAreLeftAlone() throws {
        try png("existing.png")
        let rec = Recorder(), s = service(rec)
        s.apply(rules: [rule()])
        settle(s); drain(s)
        XCTAssertEqual(rec.count, 0)
    }

    func testPartialDownloadsAreSkipped() throws {
        let rec = Recorder(), s = service(rec)
        s.apply(rules: [rule()])
        try png("movie.crdownload")
        settle(s); settle(s); drain(s)
        XCTAssertEqual(rec.count, 0)
    }

    func testFilesTheTargetCannotBeMadeFromAreSkipped() throws {
        let rec = Recorder(), s = service(rec)
        s.apply(rules: [rule(.jpg)])
        try png("song.mp3")
        settle(s); settle(s); drain(s)
        XCTAssertEqual(rec.count, 0, "an MP3 can't become a JPG")
    }

    func testOwnOutputIsNotConvertedAgain() throws {
        let rec = Recorder(), s = service(rec, writeOutput: true)
        s.apply(rules: [rule(.png)])
        try png("shot.heic")
        for _ in 0..<6 { s.tick(); drain(s) }
        XCTAssertEqual(rec.count, 1)
    }

    func testDisabledRuleDoesNothing() throws {
        let rec = Recorder(), s = service(rec)
        s.apply(rules: [rule(enabled: false)])
        try png("new.png")
        settle(s); drain(s)
        XCTAssertEqual(rec.count, 0)
    }

    func testMissingFolderDoesNotCrash() {
        let rec = Recorder(), s = service(rec)
        s.apply(rules: [WatchRule(folder: "/definitely/not/here-\(UUID().uuidString)", format: "jpg", enabled: true)])
        settle(s)
        XCTAssertEqual(rec.count, 0)
    }

    func testRemovingARuleStopsWatching() throws {
        let rec = Recorder(), s = service(rec)
        s.apply(rules: [rule()])
        s.apply(rules: [])
        try png("new.png")
        settle(s); drain(s)
        XCTAssertEqual(rec.count, 0)
    }

    func testResultsAreReported() throws {
        let rec = Recorder()
        let got = expectation(description: "result")
        let s = service(rec, writeOutput: true) { summary in if summary.outputs.count == 1 { got.fulfill() } }
        s.apply(rules: [rule()])
        try png("a.heic")
        settle(s)
        wait(for: [got], timeout: 5)
    }
}

final class WatchRuleStoreTests: XCTestCase {
    func testRoundTrip() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "convrt-test-\(UUID().uuidString)"))
        XCTAssertEqual(WatchRuleStore.load(defaults: defaults), [])
        let rules = [WatchRule(folder: "/tmp/a", format: "jpg", enabled: true), WatchRule(folder: "/tmp/b", format: "mp3", enabled: false)]
        WatchRuleStore.save(rules, defaults: defaults)
        XCTAssertEqual(WatchRuleStore.load(defaults: defaults), rules)
    }

    func testGarbageInDefaultsGivesNoRules() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "convrt-test-\(UUID().uuidString)"))
        defaults.set("not json", forKey: WatchRuleStore.key)
        XCTAssertEqual(WatchRuleStore.load(defaults: defaults), [])
    }
}
