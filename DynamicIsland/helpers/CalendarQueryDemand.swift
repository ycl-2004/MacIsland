import Foundation

struct CalendarQueryDemand: Equatable {
    var dayEvents = false
    var reminderEvents = false
    var lockScreenEvents = false
    var isActive: Bool { dayEvents || lockScreenEvents }

    init(policy: AtollRuntimePolicy = .init(), remindersEnabled: Bool = false,
         lockScreenEnabled: Bool = false, hasAccess: Bool = false) {
        reminderEvents = hasAccess && remindersEnabled
        dayEvents = hasAccess && ((!policy.isLocked && policy.calendarVisible) || remindersEnabled)
        lockScreenEvents = hasAccess && policy.isLocked && lockScreenEnabled
    }
}
