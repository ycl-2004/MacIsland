import AppKit
import Combine
import Foundation

/// Event-driven signals, no new polling timer. Multiple windows contribute
/// independently so closing one display cannot stop a visible Stats surface.
final class RuntimePolicyMonitor: ObservableObject {
    static let shared = RuntimePolicyMonitor()
    @Published private(set) var state = AtollRuntimePolicy()
    private var statsSurfaces = Set<String>()
    private var calendarSurfaces = Set<String>()
    private var tokens: [(NotificationCenter, NSObjectProtocol)] = []

    private init() {
        state.isLowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        state.isLocked = LockScreenManager.isLockedSnapshot
        guard !AppRuntimeEnvironment.isTesting else { return }
        observe(NotificationCenter.default, .NSProcessInfoPowerStateDidChange) { [weak self] in
            self?.update(lowPower: ProcessInfo.processInfo.isLowPowerModeEnabled)
        }
        observe(DistributedNotificationCenter.default(), Notification.Name("com.apple.screenIsLocked")) { [weak self] in self?.update(locked: true) }
        observe(DistributedNotificationCenter.default(), Notification.Name("com.apple.screenIsUnlocked")) { [weak self] in self?.update(locked: false) }
    }

    deinit { for (center, token) in tokens { center.removeObserver(token) } }

    func setStatsSurface(_ id: String, visible: Bool) {
        if visible { statsSurfaces.insert(id) } else { statsSurfaces.remove(id) }
        var next = state
        next.statsVisible = !statsSurfaces.isEmpty
        if next != state { state = next }
    }

    func setCalendarSurface(_ id: String, visible: Bool) {
        if visible { calendarSurfaces.insert(id) } else { calendarSurfaces.remove(id) }
        var next = state
        next.calendarVisible = !calendarSurfaces.isEmpty
        if next != state { state = next }
    }

    private func update(locked: Bool? = nil, lowPower: Bool? = nil) {
        var next = state
        if let locked { next.isLocked = locked }
        if let lowPower { next.isLowPower = lowPower }
        if next != state { state = next }
    }

    private func observe(_ center: NotificationCenter, _ name: Notification.Name, action: @escaping () -> Void) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { _ in action() }
        tokens.append((center, token))
    }
}
