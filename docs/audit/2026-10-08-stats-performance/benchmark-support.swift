import Foundation
import Combine
import Defaults

enum ProbePreferences {
    static let name = "AtollStatsProbe-" + UUID().uuidString
    static let suite = UserDefaults(suiteName: name)!
}
extension Defaults.Keys {
    static let enableStatsFeature = Key<Bool>("enableStatsFeature", default: false, suite: ProbePreferences.suite)
    static let statsStopWhenNotchCloses = Key<Bool>("statsStopWhenNotchCloses", default: true, suite: ProbePreferences.suite)
    static let statsUpdateInterval = Key<Double>("statsUpdateInterval", default: 1.0, suite: ProbePreferences.suite)
    static let showCpuGraph = Key<Bool>("showCpuGraph", default: true, suite: ProbePreferences.suite)
    static let showMemoryGraph = Key<Bool>("showMemoryGraph", default: true, suite: ProbePreferences.suite)
    static let showGpuGraph = Key<Bool>("showGpuGraph", default: true, suite: ProbePreferences.suite)
    static let showNetworkGraph = Key<Bool>("showNetworkGraph", default: false, suite: ProbePreferences.suite)
    static let showDiskGraph = Key<Bool>("showDiskGraph", default: false, suite: ProbePreferences.suite)
}
@MainActor final class RuntimePolicyMonitor: ObservableObject {
    static let shared = RuntimePolicyMonitor()
    @Published var state = AtollRuntimePolicy()
    func setStatsSurface(_ id: String, visible: Bool) { state.statsVisible = visible }
}
func debugLog(_ message: @autoclosure () -> String) {}
