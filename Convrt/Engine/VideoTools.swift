import AVFoundation
import ImageIO
import UniformTypeIdentifiers

/// Video conversion and tools, offline, on AVFoundation (MP4, MOV, M4V and 3GP in; MP4 and MOV out).
/// Call from a background queue: exports block until they finish.
enum VideoTools {
    // MARK: - Opening and exporting

    private static func openVideo(_ url: URL) throws -> AVURLAsset {
        let asset = AVURLAsset(url: url)
        guard asset.isReadable, !asset.tracks.isEmpty else {
            throw ToolError("Couldn’t read this video. Its format may not be supported on this Mac.")
        }
        return asset
    }

    static func duration(of url: URL) -> Double {
        let d = AVURLAsset(url: url).duration.seconds
        return d.isFinite ? d : 0
    }

    private static func fileType(for url: URL) -> AVFileType {
        ["mp4", "m4v", "3gp"].contains(url.pathExtension.lowercased()) ? .mp4 : .mov
    }

    private static func export(_ asset: AVAsset, preset: String, type: AVFileType, to out: URL,
                               timeRange: CMTimeRange? = nil) throws {
        guard let session = AVAssetExportSession(asset: asset, presetName: preset),
              session.supportedFileTypes.contains(type) else {
            throw ToolError("This Mac can’t export that kind of file.")
        }
        session.outputURL = out
        session.outputFileType = type
        if let timeRange { session.timeRange = timeRange }
        let done = DispatchSemaphore(value: 0)
        session.exportAsynchronously { done.signal() }
        done.wait()
        guard session.status == .completed else {
            try? FileManager.default.removeItem(at: out)
            throw ToolError("Couldn’t export: " + (session.error?.localizedDescription ?? "unknown error"))
        }
    }

    /// Fast, lossless export first; a full re-encode if the container won't take the streams as they are.
    private static func exportKeepingQuality(_ asset: AVAsset, type: AVFileType, to out: URL) throws {
        do { try export(asset, preset: AVAssetExportPresetPassthrough, type: type, to: out) }
        catch { try export(asset, preset: AVAssetExportPresetHighestQuality, type: type, to: out) }
    }

    private static func sibling(of url: URL, suffix: String, ext: String) -> URL {
        OutputNaming.uniqueURL(dir: AppSettings.outputDirectory(for: url),
                               base: url.deletingPathExtension().lastPathComponent, suffix: suffix, ext: ext)
    }

    // MARK: - Convert

    /// Video to MP4 or MOV.
    static func convert(_ url: URL, to format: OutputFormat, dir: URL, base: String) throws -> URL {
        let asset = try openVideo(url)
        let out = OutputNaming.uniqueURL(dir: dir, base: base, ext: format.fileExtension)
        try export(asset, preset: AVAssetExportPresetHighestQuality, type: format == .mov ? .mov : .mp4, to: out)
        return out
    }

    /// The sound of a video as M4A, WAV, AIFF, FLAC or MP3.
    static func extractAudio(_ url: URL, to format: OutputFormat, dir: URL, base: String) throws -> URL {
        let asset = try openVideo(url)
        guard !asset.tracks(withMediaType: .audio).isEmpty else { throw ToolError("This video has no audio.") }
        if format == .m4a {
            let out = OutputNaming.uniqueURL(dir: dir, base: base, ext: "m4a")
            try export(asset, preset: AVAssetExportPresetAppleM4A, type: .m4a, to: out)
            return out
        }
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent("convrt-\(UUID().uuidString).m4a")
        defer { try? FileManager.default.removeItem(at: temp) }
        try export(asset, preset: AVAssetExportPresetAppleM4A, type: .m4a, to: temp)
        return try AudioConverter.convert(temp, to: format, dir: dir, base: base)
    }

    // MARK: - Tools

    /// Same video without its sound track.
    static func mute(_ url: URL) throws -> URL {
        let asset = try openVideo(url)
        let videoTracks = asset.tracks(withMediaType: .video)
        guard !videoTracks.isEmpty else { throw ToolError("This file has no video.") }
        guard !asset.tracks(withMediaType: .audio).isEmpty else { throw ToolError("This video has no sound to remove.") }

        let composition = AVMutableComposition()
        for track in videoTracks {
            guard let copy = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else { continue }
            copy.preferredTransform = track.preferredTransform
            try copy.insertTimeRange(CMTimeRange(start: .zero, duration: asset.duration), of: track, at: .zero)
        }
        let ext = url.pathExtension.isEmpty ? "mov" : url.pathExtension.lowercased()
        let out = sibling(of: url, suffix: "-muted", ext: ext)
        try exportKeepingQuality(composition, type: fileType(for: url), to: out)
        return out
    }

    /// A still from the middle of the video (or `seconds` in), as a JPEG next to it.
    static func snapshot(_ url: URL, at seconds: Double? = nil) throws -> URL {
        let asset = try openVideo(url)
        guard !asset.tracks(withMediaType: .video).isEmpty else { throw ToolError("This file has no video.") }
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        let time = CMTime(seconds: seconds ?? asset.duration.seconds / 2, preferredTimescale: 600)
        let image: CGImage
        do { image = try generator.copyCGImage(at: time, actualTime: nil) }
        catch { throw ToolError("Couldn’t grab a frame from this video.") }

        let out = sibling(of: url, suffix: "-frame", ext: "jpg")
        guard let dest = CGImageDestinationCreateWithURL(out as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw ToolError("Couldn’t create the image file.")
        }
        CGImageDestinationAddImage(dest, image, [kCGImageDestinationLossyCompressionQuality: 0.92] as CFDictionary)
        guard CGImageDestinationFinalize(dest) else {
            try? FileManager.default.removeItem(at: out)
            throw ToolError("Couldn’t write the image file.")
        }
        return out
    }

    /// Keeps only `start`..`end` seconds. `end` past the clip's length is cut back to the end.
    static func trim(_ url: URL, from start: Double, to end: Double) throws -> URL {
        let asset = try openVideo(url)
        let length = asset.duration.seconds
        guard start >= 0, start < end, start < length else {
            throw ToolError("Those times don’t fit this clip, which is \(TimeParser.format(length)) long.")
        }
        let range = CMTimeRange(start: CMTime(seconds: start, preferredTimescale: 600),
                                end: CMTime(seconds: min(end, length), preferredTimescale: 600))
        let ext = url.pathExtension.isEmpty ? "mov" : url.pathExtension.lowercased()
        let out = sibling(of: url, suffix: "-trimmed", ext: ext)
        try export(asset, preset: AVAssetExportPresetHighestQuality, type: fileType(for: url), to: out, timeRange: range)
        return out
    }
}
