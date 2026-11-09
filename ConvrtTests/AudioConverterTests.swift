import XCTest
import AVFoundation
@testable import Convrt

final class AudioConverterTests: XCTestCase {
    private var dir: URL!
    private let fm = FileManager.default

    override func setUpWithError() throws {
        dir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try? fm.removeItem(at: dir) }

    /// Writes `seconds` of a 440 Hz sine as 16-bit PCM WAV.
    private func makeWAV(_ name: String = "tone.wav", seconds: Double = 1.0, rate: Double = 44100, channels: Int = 1) throws -> URL {
        let url = dir.appendingPathComponent(name)
        let settings: [String: Any] = [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: rate,
                                       AVNumberOfChannelsKey: channels, AVLinearPCMBitDepthKey: 16,
                                       AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false]
        let file = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
        let frames = AVAudioFrameCount(seconds * rate)
        let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: frames)!
        buffer.frameLength = frames
        for c in 0..<channels {
            let p = buffer.floatChannelData![c]
            for i in 0..<Int(frames) { p[i] = Float(0.4 * sin(2 * Double.pi * 440 * Double(i) / rate)) }
        }
        try file.write(from: buffer)
        return url
    }

    private func info(_ url: URL) throws -> (seconds: Double, channels: Int) {
        let f = try AVAudioFile(forReading: url)
        return (Double(f.length) / f.fileFormat.sampleRate, Int(f.fileFormat.channelCount))
    }

    private func convert(_ src: URL, _ format: OutputFormat) throws -> URL {
        try AudioConverter.convert(src, to: format, dir: dir, base: src.deletingPathExtension().lastPathComponent)
    }

    func testWavToM4AKeepsDuration() throws {
        let out = try convert(try makeWAV(), .m4a)
        XCTAssertEqual(out.pathExtension, "m4a")
        XCTAssertEqual(try info(out).seconds, 1.0, accuracy: 0.1)
    }

    func testWavToAIFFKeepsDuration() throws {
        let out = try convert(try makeWAV(), .aiff)
        XCTAssertEqual(out.pathExtension, "aiff")
        XCTAssertEqual(try info(out).seconds, 1.0, accuracy: 0.01)
    }

    func testWavToFLACKeepsDuration() throws {
        let out = try convert(try makeWAV(), .flac)
        XCTAssertEqual(try info(out).seconds, 1.0, accuracy: 0.01)
    }

    func testM4AToWAVRoundTrip() throws {
        let m4a = try convert(try makeWAV(), .m4a)
        let wav = try convert(m4a, .wav)
        XCTAssertEqual(wav.pathExtension, "wav")
        XCTAssertEqual(try info(wav).seconds, 1.0, accuracy: 0.1)
    }

    func testStereoIsPreserved() throws {
        let out = try convert(try makeWAV("st.wav", channels: 2), .aiff)
        XCTAssertEqual(try info(out).channels, 2)
    }

    func testWavToMP3AndBackToWav() throws {
        try XCTSkipUnless(MP3Encoder.isAvailable, "no lame/ffmpeg installed")
        let mp3 = try convert(try makeWAV(), .mp3)
        XCTAssertEqual(mp3.pathExtension, "mp3")
        XCTAssertEqual(try info(mp3).seconds, 1.0, accuracy: 0.15)
        let wav = try convert(mp3, .wav)
        XCTAssertEqual(try info(wav).seconds, 1.0, accuracy: 0.15)
    }

    func testMP3WithoutEncoderGivesClearError() throws {
        let src = try makeWAV()
        XCTAssertThrowsError(try AudioConverter.convert(src, to: .mp3, dir: dir, base: "x", mp3Engine: nil)) { error in
            XCTAssertTrue(error.localizedDescription.contains("lame"), error.localizedDescription)
        }
    }

    func testCorruptAudioFailsWithoutCrashing() throws {
        let bad = dir.appendingPathComponent("bad.wav")
        try Data((0..<500).map { _ in UInt8.random(in: 0...255) }).write(to: bad)
        XCTAssertThrowsError(try convert(bad, .m4a))
    }

    func testZeroByteAudioFails() throws {
        let empty = dir.appendingPathComponent("empty.mp3")
        fm.createFile(atPath: empty.path, contents: Data())
        XCTAssertThrowsError(try convert(empty, .wav))
    }

    func testOutputNeverOverwrites() throws {
        let src = try makeWAV()
        let a = try convert(src, .aiff), b = try convert(src, .aiff)
        XCTAssertNotEqual(a, b)
        XCTAssertTrue(fm.fileExists(atPath: a.path) && fm.fileExists(atPath: b.path))
    }

    func testEncoderDiscoveryFindsExecutableInGivenFolders() throws {
        let bin = dir.appendingPathComponent("bin"); try fm.createDirectory(at: bin, withIntermediateDirectories: true)
        XCTAssertNil(MP3Encoder.findEngine(searchDirs: [bin]))
        let fake = bin.appendingPathComponent("lame")
        try "#!/bin/sh\nexit 0\n".write(to: fake, atomically: true, encoding: .utf8)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fake.path)
        XCTAssertEqual(MP3Encoder.findEngine(searchDirs: [bin]), .lame(fake))
    }

    func testCatalogOffersAudioFormatsForAudioFiles() {
        let fromMP3 = FormatCatalog.formats(for: [URL(fileURLWithPath: "/tmp/a.mp3")])
        XCTAssertTrue(fromMP3.contains(.wav) && fromMP3.contains(.m4a))
        XCTAssertFalse(fromMP3.contains(.mp3), "never offer converting to itself")
        let fromWAV = FormatCatalog.formats(for: [URL(fileURLWithPath: "/tmp/a.wav")])
        XCTAssertEqual(fromWAV.contains(.mp3), MP3Encoder.isAvailable)
    }
}
