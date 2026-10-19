import AppKit
import ApplicationServices
import Foundation

@main struct SettingsProbe {
    @MainActor static func main() async throws {
        guard AXIsProcessTrusted() else {
            print("Accessibility is not granted to this inspection process; no permission requested.")
            return
        }
        var running = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == "com.apple.systempreferences" })
        if running == nil, CommandLine.arguments.contains("--open") {
            let url = URL(fileURLWithPath: "/System/Applications/System Settings.app")
            running = try await withCheckedThrowingContinuation { continuation in
                NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()) { app, error in
                    if let error { continuation.resume(throwing: error) }
                    else if let app { continuation.resume(returning: app) }
                    else { continuation.resume(throwing: NSError(domain: "MenuBarSettingsProbe", code: 1)) }
                }
            }
            try await Task.sleep(for: .seconds(2))
        }
        guard let app = running else { print("System Settings is not running."); return }
        print("System Settings PID: \(app.processIdentifier); terminated: \(app.isTerminated)")
        if CommandLine.arguments.contains("--show-menu-bar") {
            app.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
            if let link = URL(string: "x-apple.systempreferences:com.apple.ControlCenter-Settings.extension") {
                NSWorkspace.shared.open(link)
                try await Task.sleep(for: .seconds(2))
            }
        }
        let root = AXUIElementCreateApplication(app.processIdentifier)
        if CommandLine.arguments.contains("--show-menu-bar") {
            var candidate: AXUIElement?
            var nodes = 0
            func find(_ element: AXUIElement, parents: [AXUIElement]) {
                guard candidate == nil, nodes < 6000, parents.count < 30 else { return }
                nodes += 1
                for key in [kAXTitleAttribute, kAXValueAttribute, kAXDescriptionAttribute] {
                    var value: CFTypeRef?
                    if AXUIElementCopyAttributeValue(element, key as CFString, &value) == .success,
                       let text = value as? String, text == "Menu Bar" {
                        for node in ([element] + parents.reversed()) {
                            var role: CFTypeRef?
                            if AXUIElementCopyAttributeValue(node, kAXRoleAttribute as CFString, &role) == .success,
                               (role as? String) == kAXRowRole { candidate = node; return }
                        }
                    }
                }
                var children: CFTypeRef?
                if AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &children) == .success,
                   let children = children as? [AXUIElement] {
                    for child in children { find(child, parents: parents + [element]) }
                }
            }
            find(root, parents: [])
            if let row = candidate {
                let result = AXUIElementSetAttributeValue(row, kAXSelectedAttribute as CFString, kCFBooleanTrue)
                print("Selected Menu Bar sidebar row: \(result.rawValue)")
                try await Task.sleep(for: .seconds(2))
            } else { print("Menu Bar sidebar row not found.") }
        }
        var count = 0
        var visited = 0
        var matches: [[String: String]] = []
        func visit(_ element: AXUIElement, depth: Int, path: String) {
            guard depth < 30, visited < 6000 else { return }
            visited += 1
            for key in [kAXTitleAttribute, kAXValueAttribute, kAXDescriptionAttribute] {
                var value: CFTypeRef?
                if AXUIElementCopyAttributeValue(element, key as CFString, &value) == .success,
                   let text = value as? String, text == "Atoll" || text == "YC Island" || text == "Allow in the Menu Bar" || text == "YC Island Tests" {
                    var role: CFTypeRef?
                    var identifier: CFTypeRef?
                    AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role)
                    AXUIElementCopyAttributeValue(element, kAXIdentifierAttribute as CFString, &identifier)
                    matches.append(["text": text, "attribute": key, "role": role as? String ?? "", "identifier": identifier as? String ?? "", "path": path])
                    print("Matched settings label: \(text); attribute: \(key); role: \(role as? String ?? ""); path: \(path)")
                    if text == "Atoll" || text == "YC Island" { count += 1 }
                }
            }
            var children: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &children) == .success,
               let children = children as? [AXUIElement] {
                for (index, child) in children.enumerated() { visit(child, depth: depth + 1, path: path + "/" + String(index)) }
            }
        }
        visit(root, depth: 0, path: "root")
        print("Matching Atoll/YC labels in the current settings tree: \(count); elements inspected: \(visited)")
        let json = try JSONSerialization.data(withJSONObject: ["matches": matches, "elementsInspected": visited, "settingsPID": app.processIdentifier], options: [.prettyPrinted, .sortedKeys])
        try json.write(to: URL(fileURLWithPath: "/tmp/yc-island-menu-bar-ui-final.json"))
    }
}
