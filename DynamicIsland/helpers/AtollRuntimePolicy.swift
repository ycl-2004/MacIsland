import Foundation

/// Pure decisions, shared by demand-driven samplers and connection refresh.
/// Critical event delivery and timer deadlines do not use these gates.
struct AtollRuntimePolicy: Equatable {
    var isLocked = false
    var isLowPower = false
    var statsVisible = false
    var calendarVisible = false

    func shouldSampleStats(enabled: Bool, keepInBackground: Bool, alreadySampling: Bool) -> Bool {
        enabled && !isLocked && (statsVisible || (keepInBackground && alreadySampling))
    }

    func statsInterval(configured: TimeInterval) -> TimeInterval {
        let normal = configured.isFinite ? min(60, max(1, configured)) : 1
        return max(normal, statsVisible ? (isLowPower ? 3 : 1) : (isLowPower ? 10 : 5))
    }

    func agentRefreshInterval(conversationOpen: Bool) -> Duration {
        if isLocked { return .seconds(15) }
        if isLowPower { return .seconds(conversationOpen ? 3 : 10) }
        return .seconds(conversationOpen ? 1 : 3)
    }
}
