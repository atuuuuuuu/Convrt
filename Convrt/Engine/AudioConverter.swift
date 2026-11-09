import AVFoundation

/// Audio to audio, fully offline. Reads anything Core Audio reads (MP3, WAV, AIFF, M4A/AAC, FLAC, CAF)
/// and writes WAV, AIFF, M4A (AAC) and FLAC; MP3 goes through `MP3Encoder`.
enum AudioConverter {
    static func convert(_ url: URL, to format: OutputFormat, dir: URL, base: String,
                        mp3Engine: MP3Encoder.Engine? = MP3Encoder.findEngine()) throws -> URL {
        let source = try openSource(url)

        if format == .mp3 {
            guard let engine = mp3Engine else { throw AudioError(MP3Encoder.installHint) }
            let temp = FileManager.default.temporaryDirectory.appendingPathComponent("convrt-\(UUID().uuidString).wav")
            defer { try? FileManager.default.removeItem(at: temp) }
            try write(source, to: temp, format: .wav)
            let out = OutputNaming.uniqueURL(dir: dir, base: base, ext: "mp3")
            try MP3Encoder.encode(wav: temp, to: out, engine: engine)
            return out
        }

        let out = OutputNaming.uniqueURL(dir: dir, base: base, ext: format.fileExtension)
        do {
            try write(source, to: out, format: format)
        } catch {
            try? FileManager.default.removeItem(at: out)
            throw error
        }
        return out
    }

    // MARK: - Reading

    static func openSource(_ url: URL) throws -> AVAudioFile {
        let file: AVAudioFile
        do { file = try AVAudioFile(forReading: url) }
        catch { throw AudioError("Couldn’t read this audio file. It may be corrupt or in an unsupported format.") }
        guard file.length > 0 else { throw AudioError("This audio file is empty.") }
        return file
    }

    // MARK: - Writing

    private static func settings(for format: OutputFormat, rate: Double, channels: AVAudioChannelCount) throws -> [String: Any] {
        switch format {
        case .wav, .aiff:
            return [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: rate, AVNumberOfChannelsKey: channels,
                    AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false,
                    AVLinearPCMIsBigEndianKey: format == .aiff]
        case .m4a:
            return [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: rate, AVNumberOfChannelsKey: channels,
                    AVEncoderBitRateKey: min(256_000, 96_000 * Int(channels)),
                    AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue]
        case .flac:
            return [AVFormatIDKey: kAudioFormatFLAC, AVSampleRateKey: rate, AVNumberOfChannelsKey: channels]
        default:
            throw AudioError("\(format.label) isn’t an audio format Convrt can write.")
        }
    }

    private static func write(_ source: AVAudioFile, to out: URL, format: OutputFormat) throws {
        let rate = source.fileFormat.sampleRate
        let channels = source.fileFormat.channelCount
        let dest = try AVAudioFile(forWriting: out,
                                   settings: try settings(for: format, rate: rate, channels: channels),
                                   commonFormat: .pcmFormatFloat32, interleaved: false)
        let capacity: AVAudioFrameCount = 16_384
        guard let buffer = AVAudioPCMBuffer(pcmFormat: source.processingFormat, frameCapacity: capacity) else {
            throw AudioError("Not enough memory to convert this file.")
        }
        source.framePosition = 0
        while source.framePosition < source.length {
            try source.read(into: buffer, frameCount: capacity)
            if buffer.frameLength == 0 { break }
            try dest.write(from: buffer)
        }
    }
}
