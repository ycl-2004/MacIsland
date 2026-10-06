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

// Reusable control faces for the lock screen music panel: the capsule
// playback buttons and the text backdrop used behind glass surfaces.

import SwiftUI

/// Apple's transport-control feedback: the tint fills the whole circular
/// target (never a ring hugging the glyph), deepens on press, and the button
/// dips slightly while it is held.
private struct PanelControlButtonStyle: ButtonStyle {
    let restingOpacity: Double
    let isHovering: Bool
    let appearance: LockScreenTextStyle

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                Circle()
                    .fill(appearance.primary(opacity: opacity(isPressed: configuration.isPressed)))
            )
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(
                .easeOut(duration: configuration.isPressed ? 0.06 : 0.15),
                value: configuration.isPressed
            )
    }

    private func opacity(isPressed: Bool) -> Double {
        if isPressed {
            return min(max(restingOpacity + 0.16, 0.26), 0.4)
        }
        if isHovering {
            return min(max(restingOpacity + 0.08, 0.15), 0.32)
        }
        return restingOpacity
    }
}

// Nested under the panel that uses them so the generic names stay out of
// the module namespace.
extension LockScreenMusicPanel {
    struct PanelControlButton: View {
        /// What the button draws. Modelling this as one value rather than an icon
        /// name plus an optional direction keeps the two from disagreeing, and
        /// keeps the parameter list shorter than it was before skip arrows existed.
        enum Glyph {
            case symbol(String)
            /// Chevrons that march in this direction on press, the way Apple's do.
            case skipArrows(SkipTrackGlyph.Direction)

            var symbolName: String {
                switch self {
                case .symbol(let name): return name
                case .skipArrows(let direction): return direction == .forward ? "forward.fill" : "backward.fill"
                }
            }
        }

        let glyph: Glyph
        let frameSize: CGFloat
        let iconSize: CGFloat
        let iconColor: Color
        let backgroundOpacity: Double
        let interaction: Interaction
        let symbolEffect: SymbolEffectStyle
        let action: () -> Void

        @LockScreenStyle private var appearance
        @State private var isHovering = false
        @State private var pressOffset: CGFloat = 0
        @State private var rotationAngle: Double = 0
        @State private var wiggleToken: Int = 0
        @State private var skipToken: Int = 0

        var body: some View {
            Button(action: {
                triggerPressEffect()
                action()
            }) {
                iconView
                    .frame(width: frameSize, height: frameSize)
                    .contentShape(Circle())
            }
            .buttonStyle(
                PanelControlButtonStyle(
                    restingOpacity: backgroundOpacity,
                    isHovering: isHovering,
                    appearance: appearance
                )
            )
            .offset(x: pressOffset)
            .rotationEffect(.degrees(rotationAngle))
            .onHover { hovering in
                withAnimation(.smooth(duration: 0.24)) {
                    isHovering = hovering
                }
            }
        }

        private func triggerPressEffect() {
            if case .skipArrows = glyph {
                skipToken += 1
            }

            switch interaction {
            case .none:
                return
            case .nudge(let amount):
                withAnimation(.spring(response: 0.2, dampingFraction: 0.55)) {
                    pressOffset = amount
                }

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.72)) {
                        pressOffset = 0
                    }
                }
            case .wiggle(let direction):
                guard #available(macOS 14.0, *) else { return }
                wiggleToken += 1
                let angle: Double = direction == .clockwise ? 10 : -10

                withAnimation(.spring(response: 0.18, dampingFraction: 0.5)) {
                    rotationAngle = angle
                }

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.75)) {
                        rotationAngle = 0
                    }
                }
            }
        }

        @ViewBuilder
        private var iconView: some View {
            switch glyph {
            case .skipArrows(let direction):
                SkipTrackGlyph(direction: direction, size: iconSize, trigger: skipToken)
                    .foregroundStyle(iconColor)
            case .symbol:
                symbolIconView
            }
        }

        @ViewBuilder
        private var symbolIconView: some View {
            // The glyph swap rides whatever animation is ambient when `isPlaying`
            // changes, and the default is slow enough that pause reads as lagging
            // the click. Naming a fast one here pins it.
            let base = Image(systemName: glyph.symbolName)
                .font(.system(size: iconSize, weight: .medium))
                .foregroundStyle(iconColor)
                .animation(.snappy(duration: 0.16), value: glyph.symbolName)

            switch symbolEffect {
            case .replace:
                base.contentTransition(.symbolEffect(.replace))
            case .replaceAndBounce:
                if #available(macOS 14.0, *) {
                    base
                        .contentTransition(.symbolEffect(.replace))
                        .symbolEffect(.bounce, value: glyph.symbolName)
                } else {
                    base.contentTransition(.symbolEffect(.replace))
                }
            case .wiggle:
                if #available(macOS 15.0, *) {
                    base
                        .contentTransition(.symbolEffect(.replace))
                        .symbolEffect(.wiggle.byLayer, options: .nonRepeating, value: wiggleToken)
                } else {
                    base.contentTransition(.symbolEffect(.replace))
                }
            }
        }

        enum Interaction {
            case none
            case nudge(CGFloat)
            case wiggle(WiggleDirection)
        }

        enum SymbolEffectStyle {
            case replace
            case replaceAndBounce
            case wiggle
        }

        enum WiggleDirection {
            case clockwise
            case counterClockwise
        }
    }

    @available(macOS 26.0, *)
    struct GlassTextBackdrop: View {
        let cornerRadius: CGFloat

        var body: some View {
            GeometryReader { proxy in
                let dynamicFontSize = max(min(proxy.size.width, proxy.size.height) / 8, 42)

                Text("Lock Screen Liquid Glass")
                    .font(.system(size: dynamicFontSize, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.clear)
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .glassEffect(
                        .clear.interactive(),
                        in: .rect(cornerRadius: cornerRadius)
                    )
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }
}
