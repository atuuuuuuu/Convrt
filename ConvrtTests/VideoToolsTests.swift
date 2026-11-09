import XCTest
import AVFoundation
import ImageIO
@testable import Convrt

final class VideoToolsTests: XCTestCase {
    private var dir: URL!
    private let fm = FileManager.default

    override func setUpWithError() throws {
        dir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try? fm.removeItem(at: dir) }

    // MARK: - Fixtures

    private func makeSilentVideo(seconds: Double = 1, size: Int = 64, fps: Int32 = 15) throws -> URL {
        let url = dir.appendingPathComponent("silent.mov")
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: size, AVVideoHeightKey: size])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: size, kCVPixelBufferHeightKey as String: size])
        writer.add(input)
        XCTAssertTrue(writer.startWriting())
        writer.startSession(atSourceTime: .zero)
        for i in 0..<Int(seconds * Double(fps)) {
            while !input.isReadyForMoreMediaData { Thread.sleep(forTimeInterval: 0.005) }
            var buffer: CVPixelBuffer?
            CVPixelBufferCreate(nil, size, size, kCVPixelFormatType_32BGRA, nil, &buffer)
            let b = try XCTUnwrap(buffer)
            CVPixelBufferLockBaseAddress(b, [])
            memset(CVPixelBufferGetBaseAddress(b), Int32(40 + (i * 12) % 200), CVPixelBufferGetBytesPerRow(b) * size)
            CVPixelBufferUnlockBaseAddress(b, [])
            adaptor.append(b, withPresentationTime: CMTime(value: Int64(i), timescale: fps))
        }
        input.markAsFinished()
        let done = DispatchSemaphore(value: 0)
        writer.finishWriting { done.signal() }
        done.wait()
        XCTAssertEqual(writer.status, .completed, "\(String(describing: writer.error))")
        return url
    }

    private func makeWAV(seconds: Double = 1) throws -> URL {
        let url = dir.appendingPathComponent("tone.wav")
        let settings: [String: Any] = [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 44100.0, AVNumberOfChannelsKey: 1,
                                       AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false]
        let f = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
        let frames = AVAudioFrameCount(seconds * 44100)
        let buf = AVAudioPCMBuffer(pcmFormat: f.processingFormat, frameCapacity: frames)!
        buf.frameLength = frames
        for i in 0..<Int(frames) { buf.floatChannelData![0][i] = Float(0.3 * sin(2 * Double.pi * 440 * Double(i) / 44100)) }
        try f.write(from: buf)
        return url
    }

    /// A .mov with both a video and an audio track.
    private func makeVideoWithAudio() throws -> URL {
        let video = AVURLAsset(url: try makeSilentVideo()), audio = AVURLAsset(url: try makeWAV())
        let comp = AVMutableComposition()
        let range = CMTimeRange(start: .zero, duration: CMTime(seconds: 1, preferredTimescale: 600))
        let v = try XCTUnwrap(comp.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid))
        try v.insertTimeRange(range, of: try XCTUnwrap(video.tracks(withMediaType: .video).first), at: .zero)
        let a = try XCTUnwrap(comp.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid))
        try a.insertTimeRange(range, of: try XCTUnwrap(audio.tracks(withMediaType: .audio).first), at: .zero)
        let out = dir.appendingPathComponent("clip.mov")
        let session = try XCTUnwrap(AVAssetExportSession(asset: comp, presetName: AVAssetExportPresetPassthrough))
        session.outputURL = out; session.outputFileType = .mov
        let done = DispatchSemaphore(value: 0)
        session.exportAsynchronously { done.signal() }
        done.wait()
        XCTAssertEqual(session.status, .completed, "\(String(describing: session.error))")
        return out
    }

    private func tracks(_ url: URL) -> (video: Int, audio: Int, seconds: Double) {
        let a = AVURLAsset(url: url)
        return (a.tracks(withMediaType: .video).count, a.tracks(withMediaType: .audio).count, a.duration.seconds)
    }

    // MARK: - Tests

    func testConvertMovToMP4KeepsVideoAndAudio() throws {
        let out = try VideoTools.convert(try makeVideoWithAudio(), to: .mp4, dir: dir, base: "clip")
        XCTAssertEqual(out.pathExtension, "mp4")
        let t = tracks(out)
        XCTAssertEqual(t.video, 1); XCTAssertEqual(t.audio, 1)
        XCTAssertEqual(t.seconds, 1, accuracy: 0.2)
    }

    func testMuteRemovesAudioKeepsVideo() throws {
        let out = try VideoTools.mute(try makeVideoWithAudio())
        let t = tracks(out)
        XCTAssertEqual(t.video, 1); XCTAssertEqual(t.audio, 0)
        XCTAssertEqual(out.lastPathComponent, "clip-muted.mov")
    }

    func testExtractAudioToM4AAndWAV() throws {
        let src = try makeVideoWithAudio()
        let m4a = try VideoTools.extractAudio(src, to: .m4a, dir: dir, base: "clip")
        XCTAssertEqual(m4a.pathExtension, "m4a"); XCTAssertEqual(tracks(m4a).seconds, 1, accuracy: 0.2)
        let wav = try VideoTools.extractAudio(src, to: .wav, dir: dir, base: "clip")
        XCTAssertEqual(wav.pathExtension, "wav"); XCTAssertEqual(tracks(wav).seconds, 1, accuracy: 0.2)
    }

    func testExtractAudioToMP3WhenEncoderExists() throws {
        try XCTSkipUnless(MP3Encoder.isAvailable, "no lame/ffmpeg")
        let mp3 = try VideoTools.extractAudio(try makeVideoWithAudio(), to: .mp3, dir: dir, base: "clip")
        XCTAssertEqual(mp3.pathExtension, "mp3")
    }

    func testExtractAudioFromSilentVideoSaysSo() throws {
        XCTAssertThrowsError(try VideoTools.extractAudio(try makeSilentVideo(), to: .m4a, dir: dir, base: "s")) {
            XCTAssertTrue($0.localizedDescription.lowercased().contains("no audio"), $0.localizedDescription)
        }
    }

    func testSnapshotWritesAJPEGOfTheRightSize() throws {
        let out = try VideoTools.snapshot(try makeSilentVideo())
        XCTAssertEqual(out.pathExtension, "jpg")
        let src = try XCTUnwrap(CGImageSourceCreateWithURL(out as CFURL, nil))
        let p = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any])
        XCTAssertEqual(p[kCGImagePropertyPixelWidth] as? Int, 64)
    }

    func testTrimShortensTheClip() throws {
        let out = try VideoTools.trim(try makeVideoWithAudio(), from: 0.2, to: 0.7)
        XCTAssertEqual(tracks(out).seconds, 0.5, accuracy: 0.2)
        XCTAssertEqual(out.lastPathComponent, "clip-trimmed.mov")
    }

    func testTrimEndIsClampedToTheClipLength() throws {
        let out = try VideoTools.trim(try makeVideoWithAudio(), from: 0.5, to: 99)
        XCTAssertEqual(tracks(out).seconds, 0.5, accuracy: 0.2)
    }

    func testTrimRejectsBadRanges() throws {
        let src = try makeVideoWithAudio()
        XCTAssertThrowsError(try VideoTools.trim(src, from: 0.7, to: 0.2))
        XCTAssertThrowsError(try VideoTools.trim(src, from: 5, to: 9))
        XCTAssertThrowsError(try VideoTools.trim(src, from: -1, to: 0.5))
    }

    func testUnreadableVideoFailsClearly() throws {
        let bad = dir.appendingPathComponent("movie.mkv")
        try Data((0..<400).map { _ in UInt8.random(in: 0...255) }).write(to: bad)
        XCTAssertThrowsError(try VideoTools.convert(bad, to: .mp4, dir: dir, base: "movie"))
        XCTAssertThrowsError(try VideoTools.mute(bad))
        XCTAssertThrowsError(try VideoTools.snapshot(bad))
    }

    func testOutputNeverOverwrites() throws {
        let src = try makeVideoWithAudio()
        XCTAssertNotEqual(try VideoTools.mute(src), try VideoTools.mute(src))
    }

    func testCatalogOffersVideoConversionsAndTools() {
        let formats = FormatCatalog.formats(for: [URL(fileURLWithPath: "/tmp/a.mov")])
        XCTAssertTrue(formats.contains(.mp4) && formats.contains(.m4a) && formats.contains(.wav))
        XCTAssertFalse(formats.contains(.mov))
        let tools = WheelCatalog.items(for: .tools, urls: [URL(fileURLWithPath: "/tmp/a.mp4")]).map(\.action)
        XCTAssertEqual(tools, [.tool(.mute), .tool(.trim), .tool(.snapshot), .tool(.extractAudio), .tool(.info)])
    }
}

final class TimeParserTests: XCTestCase {
    func testParsesSecondsAndClockForms() {
        XCTAssertEqual(TimeParser.seconds(from: "90"), 90)
        XCTAssertEqual(TimeParser.seconds(from: "1:30"), 90)
        XCTAssertEqual(TimeParser.seconds(from: "01:02:03"), 3723)
        XCTAssertEqual(TimeParser.seconds(from: " 0:01.5 ")!, 1.5, accuracy: 0.0001)
        XCTAssertEqual(TimeParser.seconds(from: "2.25")!, 2.25, accuracy: 0.0001)
    }

    func testRejectsNonsense() {
        for bad in ["", "abc", "-5", "1:75", "1:2:3:4", "1::2", ":30"] {
            XCTAssertNil(TimeParser.seconds(from: bad), bad)
        }
    }

    func testFormatRoundTrips() {
        XCTAssertEqual(TimeParser.format(0), "0:00.0")
        XCTAssertEqual(TimeParser.format(90.5), "1:30.5")
        XCTAssertEqual(TimeParser.seconds(from: TimeParser.format(754.3))!, 754.3, accuracy: 0.06)
    }
}
