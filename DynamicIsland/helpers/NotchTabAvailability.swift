import Defaults

/// One routing rule for tabs, remembered views and shortcuts. Home is only a
/// sentinel when all tabs are off; the content surface displays settings then.
struct NotchTabAvailability {
    let tabs: [NotchViews]
    let colorPickerEnabled: Bool

    init(home: Bool, shelf: Bool, timer: Bool, stats: Bool, agents: Bool,
         extraSpace: Bool, colorPicker: Bool, order: [String] = []) {
        let candidates: [(NotchViews, Bool)] = [(.home, home), (.shelf, shelf),
            (.timer, timer), (.stats, stats), (.agents, agents), (.extraSpace, extraSpace)]
        tabs = SavedRowOrder.apply(order, to: candidates.filter { $0.1 }.map { $0.0 }, key: { String(describing: $0) })
        colorPickerEnabled = colorPicker
    }

    func contains(_ view: NotchViews) -> Bool {
        view == .colorPicker ? colorPickerEnabled : tabs.contains(view)
    }

    func resolve(_ requested: NotchViews) -> NotchViews {
        contains(requested) ? requested : (tabs.first ?? .home)
    }

    static var current: Self {
        Self(home: Defaults[.showStandardMediaControls] || Defaults[.showCalendar] || Defaults[.showMirror],
             shelf: Defaults[.dynamicShelf],
             timer: Defaults[.enableTimerFeature] && Defaults[.timerDisplayMode] == .tab,
             stats: Defaults[.enableStatsFeature], agents: Defaults[.enableAgentsFeature],
             extraSpace: Defaults[.enableExtraSpaceFeature], colorPicker: Defaults[.enableColorPickerFeature],
             order: Defaults[.notchTabOrder])
    }
}
