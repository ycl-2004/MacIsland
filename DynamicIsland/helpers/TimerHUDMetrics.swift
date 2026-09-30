import AppKit

/// Shared sizing for the two wings of the closed timer. The camera housing is
/// always the centre; neither countdown format nor control state may move it.
enum TimerHUDMetrics {
    static let wingPadding: CGFloat = 22
    static let informationSpacing: CGFloat = 8
    static let controlSpacing: CGFloat = 10
    static let countdownFont = NSFont.monospacedSystemFont(ofSize: 13, weight: .semibold)

    static func countdownWidth(totalDuration: TimeInterval, remainingTime: TimeInterval) -> CGFloat {
        // Reserve the minus sign and at least HH:MM:SS from the start. This
        // covers seconds, minutes, hours and overtime without resizing at 0,
        // 60 or 3600. Longer hour counts expand both wings together.
        let hours = Int(max(abs(totalDuration), abs(remainingTime)) / 3600)
        let hourDigits = max(2, String(hours).count)
        let widestText = "-" + String(repeating: "8", count: hourDigits) + ":88:88"
        return ceil(textWidth(widestText, font: countdownFont)) + 8
    }

    static func textWidth(_ text: String, font: NSFont) -> CGFloat {
        NSAttributedString(string: text, attributes: [.font: font]).size().width
    }

    static func wingWidth(informationWidth: CGFloat, controlsWidth: CGFloat) -> CGFloat {
        max(informationWidth, controlsWidth) + wingPadding
    }
}
