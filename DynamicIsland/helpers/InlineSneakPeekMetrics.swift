import CoreGraphics

/// The closed-notch sneak peeks that draw wider than the notch: the inline
/// music/timer title strip and the AirPods listening-mode HUD. ContentView
/// sizes its layout and AppDelegate its window from the same rule.
enum InlineSneakPeekMetrics {
    enum Kind: Equatable {
        case titleStrip
        case airPodsListeningMode
    }

    /// Album art (~32) + middle section (380) + visualizer (~32) +
    /// horizontal padding (28) + clip-shape margin (12).
    static let titleStripWidth: CGFloat = 460

    /// A listening-mode change arrives as a Bluetooth sneak peek with a
    /// negative value and the mode's symbol as its icon.
    static func isAirPodsListeningMode(_ sneakPeek: SneakPeek) -> Bool {
        sneakPeek.type == .bluetoothAudio
            && sneakPeek.value < 0
            && AirPodsListeningMode.fromHUDSymbol(sneakPeek.icon) != nil
    }

    /// The wide sneak peek the closed notch is showing, if any. The AirPods
    /// HUD wins when both apply.
    static func activeKind(
        notchState: NotchState,
        sneakPeekEnabled: Bool,
        sneakPeekStyle: SneakPeekStyle,
        expandingView: ExpandedItem,
        sneakPeek: SneakPeek
    ) -> Kind? {
        guard notchState == .closed, sneakPeekEnabled else { return nil }
        if sneakPeek.show && isAirPodsListeningMode(sneakPeek) {
            return .airPodsListeningMode
        }
        if expandingView.show,
           expandingView.type == .music || expandingView.type == .timer,
           sneakPeekStyle == .inline {
            return .titleStrip
        }
        return nil
    }
}
