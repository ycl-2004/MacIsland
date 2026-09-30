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

import SwiftUI
import Defaults

struct TimerLiveActivity: View {
    @EnvironmentObject var vm: DynamicIslandViewModel
    @ObservedObject var timerManager = TimerManager.shared
    @ObservedObject var lockScreenManager = LockScreenManager.shared
    @State private var isHovering = false
    @Default(.timerShowsCountdown) private var showsCountdown
    @Default(.timerShowsProgress) private var showsProgress
    @Default(.timerShowsLabel) private var showsLabel
    @Default(.timerProgressStyle) private var progressStyle
    @Default(.timerIconColorMode) private var colorMode
    @Default(.timerSolidColor) private var solidColor
    @Default(.timerPresets) private var timerPresets
    @Default(.timerControlWindowEnabled) private var showInlineControls

    private var notchContentHeight: CGFloat {
        max(0, vm.effectiveClosedNotchHeight - (isHovering ? 0 : 12))
    }

    private var ringStrokeWidth: CGFloat { 3 }
    private var ringWrapsIcon: Bool { showsProgress && progressStyle == .ring }
    private var showsBarProgress: Bool { showsProgress && progressStyle == .bar }

    // Size the horizontal slots from the non-hovered housing, so hovering only
    // grows the height and the middle clearance, never shifts either wing.
    private var iconWidth: CGFloat { max(28, vm.effectiveClosedNotchHeight - 12) }
    private var inlineButtonSize: CGFloat { min(max(vm.effectiveClosedNotchHeight - 4, 20), 26) }
    private var inlineIconSize: CGFloat { max(inlineButtonSize * 0.6, 12) }
    private var countdownTextWidth: CGFloat {
        TimerHUDMetrics.textWidth(timerManager.formattedRemainingTime(), font: TimerHUDMetrics.countdownFont)
    }
    private var countdownWidth: CGFloat {
        TimerHUDMetrics.countdownWidth(totalDuration: timerManager.totalDuration, remainingTime: timerManager.remainingTime)
    }
    private var labelWidth: CGFloat {
        min(140, max(44, ceil(TimerHUDMetrics.textWidth(timerManager.timerName, font: .systemFont(ofSize: 11, weight: .medium)))))
    }
    private var showsInfoSection: Bool { showsCountdown || showsLabel || showsBarProgress }
    private var infoWidth: CGFloat {
        max(showsCountdown ? countdownWidth : 0, showsLabel ? labelWidth : 0, showsBarProgress && !showsCountdown ? 64 : 0)
    }
    private var visibleInfoWidth: CGFloat {
        max(showsCountdown ? ceil(countdownTextWidth) : 0, showsLabel ? labelWidth : 0, showsBarProgress && !showsCountdown ? 64 : 0)
    }
    private var inlineControlsWidth: CGFloat {
        shouldShowInlineControls ? 3 * inlineButtonSize + 2 * TimerHUDMetrics.controlSpacing : 0
    }
    private var wingWidth: CGFloat {
        let informationWidth = iconWidth + (showsInfoSection ? TimerHUDMetrics.informationSpacing + infoWidth : 0)
        return TimerHUDMetrics.wingWidth(informationWidth: informationWidth, controlsWidth: inlineControlsWidth)
    }
    private var middleSectionWidth: CGFloat { vm.closedNotchSize.width + (isHovering ? 8 : 0) }
    private var adjustedNotchHeight: CGFloat { vm.effectiveClosedNotchHeight + (isHovering ? 8 : 0) }
    private var shouldShowInlineControls: Bool {
        showInlineControls && timerManager.allowsManualInteraction && !lockScreenManager.isLocked
    }
    private var clampedProgress: Double { min(max(timerManager.progress, 0), 1) }
    private var glyphColor: Color {
        switch colorMode {
        case .adaptive:
            return timerPresets.first { $0.id == timerManager.activePresetId }?.color ?? timerManager.timerColor
        case .solid:
            return solidColor
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            leftWingView
            Rectangle()
                .fill(.black)
                .frame(width: middleSectionWidth, height: notchContentHeight)
            rightWingView
        }
        .frame(height: adjustedNotchHeight, alignment: .center)
        .contentShape(Rectangle())
        .help(timerManager.timerName)
        .preference(key: ClosedNotchCenterShiftKey.self, value: 0)
        .preference(key: CenteredTimerActivityKey.self, value: true)
        .onHover { hovering in
            withAnimation(.notchQuick) { isHovering = hovering }
        }
    }

    private var leftWingView: some View {
        HStack(spacing: TimerHUDMetrics.informationSpacing) {
            iconSection
            if showsInfoSection {
                infoSection
            }
        }
        // A fixed frame centres the entire information group within its wing.
        // Source: https://developer.apple.com/documentation/swiftui/view/frame(width:height:alignment:)
        .frame(width: wingWidth, height: notchContentHeight, alignment: .center)
    }

    private var rightWingView: some View {
        Color.clear
            .frame(width: wingWidth, height: notchContentHeight)
            .overlay {
                if shouldShowInlineControls {
                    inlineControlsSection
                }
            }
    }

    private var infoSection: some View {
        VStack(spacing: 2) {
            // Preserve the explicit name preference, but never insert a
            // transient name that changes the footprint during a timer run.
            if showsLabel {
                Text(timerManager.timerName)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.inkSecondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            if showsCountdown {
                countdownSection
            } else if showsBarProgress {
                progressBar(width: infoWidth)
            }
        }
        .frame(width: visibleInfoWidth, alignment: .center)
    }

    private var countdownSection: some View {
        Text(timerManager.formattedRemainingTime())
            .font(.system(size: 13, weight: .semibold, design: .monospaced))
            .foregroundColor(timerManager.isOvertime ? .statusDanger : .inkPrimary)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .contentTransition(.numericText())
            .animation(.notchStandard, value: timerManager.remainingTime)
            .overlay(alignment: .bottom) {
                if showsBarProgress {
                    progressBar(width: max(countdownTextWidth, 1))
                        .alignmentGuide(.bottom) { $0[.top] - 1 }
                }
            }
    }

    private var inlineControlsSection: some View {
        HStack(spacing: TimerHUDMetrics.controlSpacing) {
            inlineControlButton(
                icon: timerManager.isPaused ? "play.fill" : "pause.fill",
                foreground: .white,
                background: .fillControl,
                help: timerManager.isPaused ? String(localized: "Resume") : String(localized: "Pause"),
                enabled: !timerManager.isFinished && !timerManager.isOvertime,
                action: togglePause
            )
            inlineControlButton(
                icon: "arrow.counterclockwise",
                foreground: .white,
                background: .fillControl,
                help: String(localized: "Restart"),
                enabled: timerManager.canRestart,
                action: timerManager.restartTimer
            )
            inlineControlButton(
                icon: "stop.fill",
                foreground: .white,
                background: timerManager.isOvertime ? Color.statusDanger.opacity(0.24) : .fillControl,
                help: String(localized: "Stop"),
                action: stopTimer
            )
        }
        .frame(height: notchContentHeight, alignment: .center)
    }

    private var iconSection: some View {
        let ringDiameter = ringWrapsIcon ? max(min(iconWidth, notchContentHeight - 2), 22) : iconWidth
        let iconSize = ringWrapsIcon ? max(ringDiameter - 12, 16) : max(18, iconWidth - 6)

        return ZStack {
            if ringWrapsIcon {
                Circle()
                    .stroke(.fillControl, lineWidth: ringStrokeWidth)
                    .frame(width: ringDiameter, height: ringDiameter)

                Circle()
                    .trim(from: 0, to: clampedProgress)
                    .stroke(glyphColor, style: StrokeStyle(lineWidth: ringStrokeWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.notchStandard, value: clampedProgress)
                    .frame(width: ringDiameter, height: ringDiameter)
            }

            Image(systemName: "timer")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(glyphColor)
                .frame(width: iconSize, height: iconSize)
        }
        .frame(width: iconWidth,
               height: notchContentHeight,
               alignment: .center)
    }
    
    private func progressBar(width: CGFloat) -> some View {
        Capsule()
            .fill(.fillControl)
            .frame(width: width, height: 3)
            .overlay(alignment: .leading) {
                Capsule()
                    .fill(glyphColor)
                    .frame(width: width * max(0, CGFloat(clampedProgress)))
                    .animation(.notchStandard, value: clampedProgress)
            }
    }

    private func inlineControlButton(
        icon: String,
        foreground: Color,
        background: Color,
        help: String,
        enabled: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: inlineIconSize, weight: .semibold))
                .foregroundStyle(foreground)
                .frame(width: inlineButtonSize, height: inlineButtonSize)
                .background(background)
                .clipShape(Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.35)
        .help(help)
        .accessibilityLabel(help)
    }

    private func togglePause() {
        guard timerManager.allowsManualInteraction else { return }
        if timerManager.isPaused {
            timerManager.resumeTimer()
        } else {
            timerManager.pauseTimer()
        }
    }

    private func stopTimer() {
        guard timerManager.allowsManualInteraction else {
            timerManager.endExternalTimer(triggerSmoothClose: false)
            return
        }
        timerManager.stopTimer()
    }

}

/// Keeps the timer's housing clearance anchored even when the frontmost app
/// has long menus. Moving just its content would put time behind the camera.
struct CenteredTimerActivityKey: PreferenceKey {
    static let defaultValue = false
    static func reduce(value: inout Bool, nextValue: () -> Bool) {
        value = value || nextValue()
    }
}

#Preview {
    TimerLiveActivity()
        .environmentObject(DynamicIslandViewModel())
        .frame(width: 500, height: 37)
        .background(.black)
        .onAppear {
            TimerManager.shared.startDemoTimer(duration: 300)
        }
}
