import Foundation

/// The helper owns SIGSTOP itself, so a failed launch cannot strand the system
/// HUD. EOF or a kqueue parent-exit event releases its leases even after SIGKILL.
final class OSDRecoveryGuardian: @unchecked Sendable {
    static let shared = OSDRecoveryGuardian()
    private let lock = NSLock()
    private var process: Process?
    private var input: FileHandle?
    private var completion: DispatchSemaphore?
    var isRunning: Bool { lock.withLock { process?.isRunning == true } }

    func suspend(_ pid: Int32) {
        lock.withLock {
            do {
                if process?.isRunning != true {
                    try? input?.close()
                    guard let url = Bundle.main.url(forResource: "AtollOSDGuardian", withExtension: nil) else { return }
                    let child = Process(), pipe = Pipe(), done = DispatchSemaphore(value: 0)
                    child.executableURL = url
                    child.standardInput = pipe
                    child.standardOutput = FileHandle.nullDevice
                    child.standardError = FileHandle.nullDevice
                    child.terminationHandler = { _ in done.signal() }
                    try child.run()
                    try? pipe.fileHandleForReading.close()
                    process = child; input = pipe.fileHandleForWriting; completion = done
                }
                try input?.write(contentsOf: Data("S \(pid)\n".utf8))
            } catch {
                // No direct SIGSTOP fallback: without a guardian, keep native HUD.
                Logger.log("System HUD recovery helper unavailable: \(error)", category: .warning)
                try? input?.close(); input = nil
            }
        }
    }
    func resumeAndClose() {
        lock.withLock {
            try? input?.write(contentsOf: Data("R\n".utf8))
            try? input?.close()
            input = nil
            // Serialize release and the next lease so an old guardian cannot
            // resume a process just stopped by its replacement.
            if process?.isRunning == true { _ = completion?.wait(timeout: .now() + 0.5) }
            process = nil; completion = nil
        }
    }
}
