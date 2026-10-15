import AppKit
import Foundation

@main struct AppLifecycle {
    @MainActor static func main() async throws {
        let action = CommandLine.arguments[1]
        let url = URL(fileURLWithPath: "/Applications/Atoll.app")
        func instances() -> [NSRunningApplication] {
            NSWorkspace.shared.runningApplications.filter { $0.bundleURL?.standardizedFileURL == url }
        }
        func describe(_ app: NSRunningApplication) -> [String: Any] {
            ["pid": app.processIdentifier, "bundlePath": app.bundleURL?.path ?? "", "executablePath": app.executableURL?.path ?? "",
             "finishedLaunching": app.isFinishedLaunching, "terminated": app.isTerminated]
        }
        var result: [String: Any] = ["action": action]
        switch action {
        case "status": result["instances"] = instances().map(describe)
        case "quit":
            let apps = instances()
            result["previousInstances"] = apps.map(describe)
            for app in apps {
                guard app.terminate() else { throw NSError(domain: "AtollInstall", code: 1, userInfo: [NSLocalizedDescriptionKey: "Normal termination was declined"]) }
            }
            let deadline = Date().addingTimeInterval(30)
            while apps.contains(where: { !$0.isTerminated }) && Date() < deadline {
                try await Task.sleep(for: .milliseconds(200))
            }
            guard apps.allSatisfy(\.isTerminated), instances().isEmpty else {
                throw NSError(domain: "AtollInstall", code: 2, userInfo: [NSLocalizedDescriptionKey: "Save/normal termination did not finish; installation cancelled"])
            }
            result["normalExitConfirmed"] = true
            result["forcedTermination"] = false
        case "launch":
            let app: NSRunningApplication = try await withCheckedThrowingContinuation { continuation in
                NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()) { app, error in
                    if let error { continuation.resume(throwing: error) }
                    else if let app { continuation.resume(returning: app) }
                    else { continuation.resume(throwing: NSError(domain: "AtollInstall", code: 3)) }
                }
            }
            let deadline = Date().addingTimeInterval(30)
            while !app.isFinishedLaunching && !app.isTerminated && Date() < deadline {
                try await Task.sleep(for: .milliseconds(200))
            }
            guard app.isFinishedLaunching, !app.isTerminated, app.bundleURL?.standardizedFileURL == url else {
                throw NSError(domain: "AtollInstall", code: 4, userInfo: [NSLocalizedDescriptionKey: "Installed app failed to finish launching"])
            }
            result["instance"] = describe(app)
        default: throw NSError(domain: "AtollInstall", code: 5)
        }
        let data = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }
}
