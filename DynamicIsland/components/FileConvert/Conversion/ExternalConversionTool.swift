import Foundation

/// Optional engines found where they are normally installed. Apps opened from
/// Finder don't inherit the shell's PATH, so Homebrew and MacPorts prefixes are
/// checked directly. Nothing is downloaded or bundled.
enum ExternalConversionTool: CaseIterable, Sendable {
    case libreOffice
    case ffmpeg

    var name: String {
        switch self {
        case .libreOffice: return "LibreOffice"
        case .ffmpeg: return "FFmpeg"
        }
    }

    private var candidates: [String] {
        switch self {
        case .libreOffice:
            let bundle = "LibreOffice.app/Contents/MacOS/soffice"
            return ["/Applications/" + bundle, FileManager.default.homeDirectoryForCurrentUser.path + "/Applications/" + bundle]
        case .ffmpeg:
            return ["/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg", "/opt/local/bin/ffmpeg"]
        }
    }

    /// A stat per candidate, cheap enough to check whenever formats are listed.
    var executable: URL? {
        candidates.first { FileManager.default.isExecutableFile(atPath: $0) }.map { URL(fileURLWithPath: $0) }
    }

    /// Runs the tool with an argument list, never through a shell. Cancelling
    /// the calling task stops the child; so does the deadline.
    func run(_ arguments: [String], timeout: TimeInterval) async throws {
        guard let executable else { throw ConversionError.engineMissing(name) }
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        // The user's environment, minus loader and test-injection settings meant for this app only.
        process.environment = ProcessInfo.processInfo.environment.filter { key, _ in
            !["DYLD_", "__XPC_", "XCTest", "XCInject"].contains { key.hasPrefix($0) }
        }
        let result: ProcessRunner.Captured
        do {
            result = try await ProcessRunner.capture(process, timeout: timeout, limit: 64 * 1024)
        } catch is CancellationError {
            throw ConversionError.cancelled
        }
        switch result.outcome {
        case .exited(0):
            return
        case .timedOut:
            throw ConversionError.engineFailed(String(localized: "\(name) took too long and was stopped."))
        case .exited:
            let lastLine = String(decoding: result.errors, as: UTF8.self)
                .split(whereSeparator: \.isNewline).last.map(String.init) ?? ""
            let summary = String(localized: "\(name) couldn’t convert the file.")
            throw ConversionError.engineFailed(lastLine.isEmpty ? summary : summary + " " + String(lastLine.prefix(200)))
        }
    }
}
