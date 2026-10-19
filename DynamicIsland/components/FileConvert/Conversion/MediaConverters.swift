import AVFoundation
import UniformTypeIdentifiers

/// Audio to AAC or uncompressed PCM through AVAudioFile.
struct AudioConverter: FileConverter {
    var routes: [ConversionRoute] { [ConversionRoute(inputs: [.audio], outputs: [.m4a, .wav, .aiff])] }

    func convert(_ source: URL, to format: ConversionFormat, in staging: URL) async throws -> [URL] {
        let destination = stagedURL(for: source, as: format, in: staging)
        let input: AVAudioFile
        do { input = try AVAudioFile(forReading: source) } catch { throw ConversionError.unreadable }
        let pcm = input.processingFormat
        var settings: [String: Any] = [AVSampleRateKey: pcm.sampleRate, AVNumberOfChannelsKey: pcm.channelCount]
        if format == .m4a {
            settings[AVFormatIDKey] = kAudioFormatMPEG4AAC
            settings[AVEncoderAudioQualityKey] = AVAudioQuality.high.rawValue
        } else {
            settings[AVFormatIDKey] = kAudioFormatLinearPCM
            settings[AVLinearPCMBitDepthKey] = 16
            settings[AVLinearPCMIsFloatKey] = false
            settings[AVLinearPCMIsBigEndianKey] = format == .aiff
            settings[AVLinearPCMIsNonInterleaved] = false
        }
        guard let buffer = AVAudioPCMBuffer(pcmFormat: pcm, frameCapacity: 32_768) else { throw ConversionError.unreadable }
        do {
            // Closed when it goes out of scope, before the service moves it.
            let output = try AVAudioFile(forWriting: destination, settings: settings,
                                         commonFormat: pcm.commonFormat, interleaved: pcm.isInterleaved)
            while input.framePosition < input.length {
                try Task.checkCancellation()
                try input.read(into: buffer)
                guard buffer.frameLength > 0 else { break }
                try output.write(from: buffer)
            }
        } catch is CancellationError {
            throw ConversionError.cancelled
        } catch {
            throw ConversionError.engineFailed(error.localizedDescription)
        }
        return [destination]
    }
}

/// QuickTime and MPEG-4 video through AVAssetExportSession. Remuxes without
/// re-encoding when the codecs fit the new container, otherwise re-encodes.
struct VideoConverter: FileConverter {
    private static let fileTypes: [String: AVFileType] = [
        ConversionFormat.mp4.id: .mp4, ConversionFormat.mov.id: .mov, ConversionFormat.m4a.id: .m4a,
    ]

    var routes: [ConversionRoute] { [ConversionRoute(inputs: [.quickTimeMovie, .mpeg4Movie], outputs: [.mp4, .mov, .m4a])] }

    func convert(_ source: URL, to format: ConversionFormat, in staging: URL) async throws -> [URL] {
        guard let fileType = Self.fileTypes[format.id] else { throw ConversionError.unsupported }
        let destination = stagedURL(for: source, as: format, in: staging)
        let asset = AVURLAsset(url: source)
        let presets = format == .m4a ? [AVAssetExportPresetAppleM4A] : [AVAssetExportPresetPassthrough, AVAssetExportPresetHighestQuality]
        var failure: Error?
        for preset in presets {
            try Task.checkCancellation()
            guard await AVAssetExportSession.compatibility(ofExportPreset: preset, with: asset, outputFileType: fileType) else { continue }
            try? FileManager.default.removeItem(at: destination)
            do {
                try await Self.export(asset, preset: preset, as: fileType, to: destination)
                return [destination]
            } catch is CancellationError {
                throw ConversionError.cancelled
            } catch {
                failure = error
            }
        }
        throw failure.map { ConversionError.engineFailed($0.localizedDescription) } ?? ConversionError.unsupported
    }

    private static func export(_ asset: AVAsset, preset: String, as fileType: AVFileType, to url: URL) async throws {
        guard let session = AVAssetExportSession(asset: asset, presetName: preset) else { throw ConversionError.unsupported }
        if #available(macOS 15, *) {
            try await session.export(to: url, as: fileType)
            return
        }
        session.outputURL = url
        session.outputFileType = fileType
        await withTaskCancellationHandler { await session.export() } onCancel: { session.cancelExport() }
        if session.status == .cancelled { throw CancellationError() }
        if let error = session.error { throw error }
        guard session.status == .completed else { throw ConversionError.noOutput }
    }
}

/// Formats macOS can't encode, when FFmpeg is installed.
struct FFmpegConverter: FileConverter {
    /// GIFs from video stop here, so a long clip can't produce an enormous file.
    static let maximumGIFSeconds = 60

    var routes: [ConversionRoute] {
        [ConversionRoute(inputs: [.movie], outputs: [.mp4, .webm, .gif, .mp3]),
         ConversionRoute(inputs: [.audio], outputs: [.mp3, .flac]),
         ConversionRoute(inputs: [.png, .jpeg, .tiff, .bmp, .gif], outputs: [.webP])]
    }
    /// Native converters win where both write a format: they use hardware encoders.
    var priority: Int { -10 }
    var isAvailable: Bool { ExternalConversionTool.ffmpeg.executable != nil }

    func convert(_ source: URL, to format: ConversionFormat, in staging: URL) async throws -> [URL] {
        let destination = stagedURL(for: source, as: format, in: staging)
        // -n refuses to overwrite; the staging folder starts empty in any case.
        try await ExternalConversionTool.ffmpeg.run(
            ["-nostdin", "-hide_banner", "-loglevel", "error", "-n", "-i", source.path]
                + Self.arguments(for: format) + [destination.path],
            timeout: 60 * 60)
        guard FileManager.default.fileExists(atPath: destination.path) else { throw ConversionError.noOutput }
        return [destination]
    }

    private static func arguments(for format: ConversionFormat) -> [String] {
        switch format {
        case .mp4:
            return ["-c:v", "libx264", "-preset", "medium", "-crf", "20", "-pix_fmt", "yuv420p",
                    "-c:a", "aac", "-b:a", "192k", "-movflags", "+faststart"]
        case .webm:
            return ["-c:v", "libvpx-vp9", "-crf", "32", "-b:v", "0", "-row-mt", "1", "-c:a", "libopus"]
        case .gif:
            return ["-t", String(maximumGIFSeconds), "-an", "-loop", "0", "-vf",
                    "fps=12,scale='min(720,iw)':-2:flags=lanczos,split[a][b];[a]palettegen[p];[b][p]paletteuse"]
        case .mp3:
            return ["-vn", "-c:a", "libmp3lame", "-q:a", "2"]
        case .flac:
            return ["-vn", "-c:a", "flac"]
        case .webP:
            return ["-c:v", "libwebp", "-quality", "90", "-loop", "0"]
        default:
            return []
        }
    }
}
