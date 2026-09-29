//
//  NotchTheme.swift
//  DynamicIsland
//
//  The notch's visual vocabulary, defined once: text levels, fills, strokes,
//  status and stats colours, the type scale and the motion curves.
//
//  The notch always draws on black, so these are fixed values rather than
//  system dynamic colours -- `.secondary` and friends resolve against the
//  window's appearance, which is not what is behind the text here. Settings
//  and other ordinary windows keep using the system colours.
//
//  Energy rules for anything drawn on the notch, which is on screen all day:
//  - An animation that can run longer than a few seconds goes through
//    `RenderServerPulse` / `LayerPulse`, so the render server plays it and
//    SwiftUI does not re-evaluate a body every frame.
//  - A `TimelineView` is capped at 30fps and pauses when nothing moves.
//  - No `.blur` or animated shadow over content that redraws continuously; a
//    black-to-clear overlay fades an edge for free, since the notch is black.
//

import SwiftUI

// MARK: - Colour

extension ShapeStyle where Self == Color {
    // Text and glyphs, strongest first.
    static var inkPrimary: Color { .white }
    static var inkSecondary: Color { .white.opacity(0.7) }
    static var inkTertiary: Color { .white.opacity(0.5) }
    static var inkQuaternary: Color { .white.opacity(0.32) }

    // Surfaces layered on the black, lightest first.
    /// Wells and empty drop zones: present, but only just.
    static var fillWell: Color { .white.opacity(0.04) }
    static var fillCard: Color { .white.opacity(0.07) }
    static var fillCardHover: Color { .white.opacity(0.11) }
    /// Buttons, chips and the unfilled part of tracks and rings.
    static var fillControl: Color { .white.opacity(0.14) }
    static var fillControlHover: Color { .white.opacity(0.2) }

    static var strokeHairline: Color { .white.opacity(0.08) }
    static var strokeRegular: Color { .white.opacity(0.15) }
    static var strokeStrong: Color { .white.opacity(0.3) }

    // Status. A little softer than the system colours, which glare at full
    // saturation on black.
    static var statusAttention: Color { Color(red: 1.0, green: 0.64, blue: 0.26) }
    static var statusSuccess: Color { Color(red: 0.34, green: 0.84, blue: 0.5) }
    static var statusDanger: Color { Color(red: 1.0, green: 0.4, blue: 0.37) }

    // One hue per system metric on the Stats tab's cards, tuned for black. The
    // detail popovers sit on the system background and keep system colours.
    static var statsCPU: Color { Color(red: 0.4, green: 0.62, blue: 1.0) }
    static var statsMemory: Color { Color(red: 0.36, green: 0.84, blue: 0.6) }
    static var statsGPU: Color { Color(red: 0.72, green: 0.56, blue: 1.0) }
    static var statsNetworkDown: Color { Color(red: 1.0, green: 0.66, blue: 0.34) }
    static var statsNetworkUp: Color { Color(red: 1.0, green: 0.46, blue: 0.46) }
    static var statsDiskRead: Color { Color(red: 0.36, green: 0.82, blue: 0.92) }
    static var statsDiskWrite: Color { Color(red: 1.0, green: 0.84, blue: 0.42) }
}

// MARK: - Type

/// Text sizes on the notch. Large numerals (timers, clocks) are sized to
/// their frames and stay where they are drawn.
enum NotchTextSize: CGFloat {
    /// Timestamps, badges, hints.
    case micro = 10
    case caption = 11
    case footnote = 12
    case body = 13
    case callout = 14
    case headline = 16
}

extension Font {
    static func notch(
        _ size: NotchTextSize,
        weight: Font.Weight = .regular,
        design: Font.Design = .default
    ) -> Font {
        .system(size: size.rawValue, weight: weight, design: design)
    }
}

// MARK: - Motion

extension Animation {
    /// Hover, press and other small state flips.
    static let notchQuick = Animation.smooth(duration: 0.18)
    /// Content changing in place.
    static let notchStandard = Animation.smooth(duration: 0.25)
    /// Things arriving, leaving or resizing.
    static let notchRelaxed = Animation.smooth(duration: 0.4)
}

// MARK: - Shape

enum NotchRadius {
    /// Buttons, fields and chips.
    static let control: CGFloat = 8
    /// Cards in a row: agents, stats, presets.
    static let card: CGFloat = 12
    /// Large panels that hold other things: the shelf, the timer composer.
    static let panel: CGFloat = 16
}
