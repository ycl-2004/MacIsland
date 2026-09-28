/*
 * Atoll (DynamicIsland)
 * Copyright (C) 2024-2026 Atoll Contributors
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program. If not, see <https://www.gnu.org/licenses/>.
 */

import AppKit
import Defaults
import SwiftUI

/// How lock-screen widgets draw text: colour, typeface and the shadow that keeps
/// it legible on the wallpaper. Widgets read it through `@LockScreenStyle`, so
/// each setting is resolved here and nowhere else.
struct LockScreenTextStyle {
    let appearance: LockScreenWidgetAppearance
    let customColor: Color
    let fontStyle: LockScreenFontStyle
    let customFontFamily: String
    let shadow: LockScreenTextShadow

    private var glyphColor: Color {
        switch appearance {
        case .dark: return .white
        case .light: return .black
        case .custom: return customColor
        }
    }

    /// Whether the text is light, so the surfaces behind it (glass, badges, pills)
    /// go dark. A custom colour decides by its own brightness.
    var usesLightGlyphs: Bool {
        switch appearance {
        case .dark: return true
        case .light: return false
        case .custom: return Self.luminance(of: customColor) > 0.5
        }
    }

    var materialColorScheme: ColorScheme {
        usesLightGlyphs ? .dark : .light
    }

    func primary(opacity: Double = 1) -> Color {
        glyphColor.opacity(opacity)
    }

    func font(size: CGFloat, weight: NSFont.Weight) -> Font {
        Font(nsFont(size: size, weight: weight) as CTFont)
    }

    func nsFont(size: CGFloat, weight: NSFont.Weight) -> NSFont {
        let system = NSFont.systemFont(ofSize: size, weight: weight)
        let design: NSFontDescriptor.SystemDesign
        switch fontStyle {
        case .standard:
            return system
        case .rounded:
            design = .rounded
        case .serif:
            design = .serif
        case .monospaced:
            design = .monospaced
        case .custom:
            let descriptor = NSFontDescriptor(fontAttributes: [
                .family: customFontFamily,
                .traits: [NSFontDescriptor.TraitKey.weight: weight.rawValue]
            ])
            if let font = NSFont(descriptor: descriptor, size: size) {
                return font
            }
            // No family picked yet, or it was uninstalled: keep the default look.
            design = .rounded
        }
        guard let descriptor = system.fontDescriptor.withDesign(design) else { return system }
        return NSFont(descriptor: descriptor, size: size) ?? system
    }

    private static func luminance(of color: Color) -> Double {
        guard let rgb = NSColor(color).usingColorSpace(.sRGB) else { return 1 }
        return 0.2126 * rgb.redComponent + 0.7152 * rgb.greenComponent + 0.0722 * rgb.blueComponent
    }
}

@propertyWrapper
struct LockScreenStyle: DynamicProperty {
    @Default(.lockScreenWidgetAppearance) private var appearance
    @Default(.lockScreenCustomTextColor) private var customColor
    @Default(.lockScreenFontStyle) private var fontStyle
    @Default(.lockScreenCustomFontFamily) private var customFontFamily
    @Default(.lockScreenTextShadow) private var shadow

    var wrappedValue: LockScreenTextStyle {
        LockScreenTextStyle(
            appearance: appearance,
            customColor: customColor,
            fontStyle: fontStyle,
            customFontFamily: customFontFamily,
            shadow: shadow
        )
    }
}

extension View {
    /// Shadow for text drawn straight on the wallpaper; it opposes the text colour.
    func lockScreenTextShadow(_ style: LockScreenTextStyle) -> some View {
        modifier(LockScreenTextShadowModifier(style: style))
    }
}

private struct LockScreenTextShadowModifier: ViewModifier {
    let style: LockScreenTextStyle

    @ViewBuilder
    func body(content: Content) -> some View {
        let tint: Color = style.usesLightGlyphs ? .black : .white
        switch style.shadow {
        case .off:
            content
        case .soft:
            content.shadow(color: tint.opacity(style.usesLightGlyphs ? 0.35 : 0.5), radius: 8, x: 0, y: 3)
        case .strong:
            content
                .shadow(color: tint.opacity(0.6), radius: 2, x: 0, y: 1)
                .shadow(color: tint.opacity(0.45), radius: 10, x: 0, y: 3)
        }
    }
}
