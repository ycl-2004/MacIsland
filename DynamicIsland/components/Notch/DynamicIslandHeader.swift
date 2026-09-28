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

import Defaults
import SwiftUI

struct DynamicIslandHeader: View {
    @EnvironmentObject var vm: DynamicIslandViewModel
    @EnvironmentObject var webcamManager: WebcamManager
    @ObservedObject var batteryModel = BatteryStatusViewModel.shared
    @ObservedObject var coordinator = DynamicIslandViewCoordinator.shared
    @ObservedObject var shelfState = ShelfStateViewModel.shared
    @ObservedObject var timerManager = TimerManager.shared
    @ObservedObject var doNotDisturbManager = DoNotDisturbManager.shared
    @State private var showColorPickerPopover = false
    @State private var showTimerPopover = false
    @State private var showPerAppVolumePopover = false
    @Default(.enableTimerFeature) var enableTimerFeature
    @Default(.timerDisplayMode) var timerDisplayMode
    @Default(.showColorPickerIcon) var showColorPickerIcon
    @Default(.enablePerAppVolume) var enablePerAppVolume
    @Default(.showPerAppVolumeIcon) var showPerAppVolumeIcon
    @Default(.showBatteryIndicator) var showBatteryIndicator
    @Default(.notchHeaderButtonOrder) private var buttonOrder
    
    /// Point size per symbol, so the row reads as one size.
    ///
    /// Equal point size is equal *cap height*, which is not equal optical size.
    /// Measured at 15pt medium: `gearshape` covers 289pt² of ink against
    /// `web.camera`'s 208 — 39% more. These sizes were solved so every glyph
    /// lands on 16pt of ink height, which is what actually makes a mixed row
    /// look even.
    private static let headerGlyphSizes: [String: CGFloat] = [
        "web.camera": 14.5,
        "eyedropper": 14.3,
        "timer": 14.4,
        "gearshape": 14.2,
        // Not solved against measured ink the way the others were: the three
        // sliders stand slightly taller than `timer`, so this trims to match.
        "slider.vertical.3": 13.8
    ]

    /// One glyph in the header row, on a common centre.
    ///
    /// The 20pt box clears the largest frame any of these symbols asks for,
    /// so none of them is clipped — a smaller box silently cuts the tall ones.
    private func headerGlyph(_ name: String, color: Color = .white) -> some View {
        Image(systemName: name)
            .foregroundColor(color)
            .font(.system(size: Self.headerGlyphSizes[name] ?? 14.4, weight: .medium))
            .frame(width: 20, height: 20)
    }

    private var headerButtons: [HeaderButton] {
        let visible = HeaderButton.allCases.filter { button in
            switch button {
            case .mirror:
                return Defaults[.showMirror]
            case .colorPicker:
                return Defaults[.enableColorPickerFeature] && showColorPickerIcon
            case .timer:
                return enableTimerFeature && timerDisplayMode == .popover
            case .perAppVolume:
                return enablePerAppVolume && showPerAppVolumeIcon
            case .settings:
                return Defaults[.settingsIconInNotch]
            }
        }
        return SavedRowOrder.apply(buttonOrder, to: visible, key: \.rawValue)
    }

    @ViewBuilder
    private func headerButton(_ button: HeaderButton) -> some View {
        let base = Button(action: { perform(button) }) {
            Capsule()
                .fill(.black)
                .frame(width: 30, height: 30)
                .overlay {
                    headerGlyph(button.glyph)
                }
        }
        .buttonStyle(PlainButtonStyle())

        switch button {
        case .colorPicker:
            headerPopover(on: base, isPresented: $showColorPickerPopover) {
                ColorPickerPopover()
            }
        case .timer:
            headerPopover(on: base, isPresented: $showTimerPopover) {
                TimerPopover()
            }
        case .perAppVolume:
            headerPopover(on: base, isPresented: $showPerAppVolumePopover) {
                PerAppVolumePopover()
            }
        case .mirror, .settings:
            base
        }
    }

    /// A popover hanging off a header button.
    ///
    /// Popover content inherits this view's environment, including the gray
    /// foreground the header sets for its tabs. Left alone, every unstyled
    /// label -- and every `.primary` / `.secondary`, which are levels *of* the
    /// inherited style -- came out that same gray, unreadable on the popover's
    /// glass. Resetting to the system label colour here covers every popover.
    private func headerPopover<Content: View>(
        on base: some View,
        isPresented: Binding<Bool>,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        base.popover(isPresented: isPresented, arrowEdge: .bottom) {
            content()
                .foregroundStyle(Color.primary)
        }
    }

    private func perform(_ button: HeaderButton) {
        switch button {
        case .mirror:
            vm.toggleCameraPreview()
        case .colorPicker:
            switch Defaults[.colorPickerDisplayMode] {
            case .panel:
                ColorPickerPanelManager.shared.toggleColorPickerPanel()
            case .popover:
                showColorPickerPopover.toggle()
            }
        case .timer:
            withAnimation(.smooth) {
                showTimerPopover.toggle()
            }
        case .perAppVolume:
            withAnimation(.smooth) {
                showPerAppVolumePopover.toggle()
            }
        case .settings:
            SettingsWindowController.shared.showWindow()
        }
    }

    /// Mirrors a popover's visibility onto the view model, and rechecks hover once
    /// it closes so the notch notices a pointer that left while it was open.
    private func popoverVisibilityChanged(_ isActive: Bool, flag: ReferenceWritableKeyPath<DynamicIslandViewModel, Bool>) {
        vm[keyPath: flag] = isActive
        if !isActive {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                vm.shouldRecheckHover.toggle()
            }
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            HStack {
                if coordinator.alwaysShowTabs || vm.notchState == .open || !shelfState.items.isEmpty {
                    TabSelectionView()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .opacity(vm.notchState == .closed ? 0 : 1)
            .blur(radius: vm.notchState == .closed ? 20 : 0)
            .animation(.smooth.delay(0.1), value: vm.notchState)
            .zIndex(2)
            .padding(8)

            if vm.notchState == .open {
                let spacerWidth = min(vm.closedNotchSize.width, 300)
                Rectangle()
                    .fill(NSScreen.screens
                        .first(where: { $0.localizedName == coordinator.selectedScreen })?.safeAreaInsets.top ?? 0 > 0 ? .black : .clear)
                    .frame(width: spacerWidth)
                    .mask {
                        NotchShape()
                    }
            }

            // 30pt targets sitting 4pt apart read as one run of buttons rather
            // than as separate ones; 8 is the gap Apple leaves between controls
            // of this size.
            HStack(spacing: 8) {
                if vm.notchState == .open {
                    ReorderableRow(items: headerButtons, spacing: 8, onReorder: { reordered in
                        buttonOrder = SavedRowOrder.merging(reordered.map(\.rawValue), into: buttonOrder)
                    }) { button in
                        headerButton(button)
                    }

                    // Screen Recording Indicator
                    if Defaults[.enableScreenRecordingDetection] && Defaults[.showRecordingIndicator] {
                        RecordingIndicator()
                            .frame(width: 30, height: 30) // Same size as other header elements
                    }

                    if Defaults[.enableDoNotDisturbDetection]
                        && Defaults[.showDoNotDisturbIndicator]
                        && doNotDisturbManager.isDoNotDisturbActive {
                        FocusIndicator()
                            .frame(width: 30, height: 30)
                            .transition(.opacity)
                    }
                }

                if vm.notchState == .open && showBatteryIndicator {
                    DynamicIslandBatteryView(
                        batteryWidth: 30,
                        isCharging: batteryModel.isCharging,
                        isInLowPowerMode: batteryModel.isInLowPowerMode,
                        isPluggedIn: batteryModel.isPluggedIn,
                        levelBattery: batteryModel.levelBattery,
                        maxCapacity: batteryModel.maxCapacity,
                        timeToFullCharge: batteryModel.timeToFullCharge,
                        isForNotification: false
                    )
                }
            }
            .font(.system(.headline, design: .rounded))
            .frame(maxWidth: .infinity, alignment: .trailing)
            .opacity(vm.notchState == .closed ? 0 : 1)
            .blur(radius: vm.notchState == .closed ? 20 : 0)
            .animation(.smooth.delay(0.1), value: vm.notchState)
            .zIndex(2)
        }
        .foregroundColor(.gray)
        .environmentObject(vm)
        .onChange(of: showColorPickerPopover) { _, isActive in
            popoverVisibilityChanged(isActive, flag: \.isColorPickerPopoverActive)
        }
        .onChange(of: showTimerPopover) { _, isActive in
            popoverVisibilityChanged(isActive, flag: \.isTimerPopoverActive)
        }
        .onChange(of: showPerAppVolumePopover) { _, isActive in
            popoverVisibilityChanged(isActive, flag: \.isPerAppVolumePopoverActive)
        }
        .onChange(of: enablePerAppVolume) { _, newValue in
            if !newValue {
                showPerAppVolumePopover = false
                vm.isPerAppVolumePopoverActive = false
            }
        }
        .onChange(of: enableTimerFeature) { _, newValue in
            if !newValue {
                showTimerPopover = false
                vm.isTimerPopoverActive = false
            }
        }
        .onChange(of: timerDisplayMode) { _, mode in
            if mode == .tab {
                showTimerPopover = false
                vm.isTimerPopoverActive = false
            }
        }
    }
}

/// The notch header's buttons, in their default order. Raw values are the keys
/// the drag order is saved under, so they must not change.
private enum HeaderButton: String, CaseIterable {
    case mirror
    case colorPicker
    case timer
    case perAppVolume
    case settings

    var glyph: String {
        switch self {
        case .mirror: return "web.camera"
        case .colorPicker: return "eyedropper"
        case .timer: return "timer"
        case .perAppVolume: return "slider.vertical.3"
        case .settings: return "gearshape"
        }
    }
}

#Preview {
    DynamicIslandHeader()
        .environmentObject(DynamicIslandViewModel())
        .environmentObject(WebcamManager.shared)
}
