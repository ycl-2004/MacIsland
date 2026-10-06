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


struct LockScreenMusicPanel: View {
    static let collapsedHeight: CGFloat = 180
    /// The width the panel starts at, and what "reset to default" restores.
    ///
    /// Also the value `Defaults.Key.lockScreenMusicPanelWidth` defaults to, so the
    /// two cannot drift apart: the stored default used to be 350 while reset put
    /// it at 420, so the app disagreed with itself about its own default.
    static let defaultCollapsedWidth: CGFloat = 390
    static var collapsedSize: CGSize {
        CGSize(width: CGFloat(Defaults[.lockScreenMusicPanelWidth]), height: collapsedHeight)
    }
    static let expandedSize = CGSize(width: 720, height: 340)

    @ObservedObject var musicManager = MusicManager.shared
    @ObservedObject private var routeManager = AudioRouteManager.shared
    @StateObject private var volumeModel = MediaOutputVolumeViewModel()
    @ObservedObject private var airPlayManager = AppleMusicAirPlayManager.shared
    @ObservedObject private var animator: LockScreenPanelAnimator
    @State private var sliderValue: Double = 0
    @State private var dragging: Bool = false
    @State private var lastDragged: Date = .distantPast
    @State private var isActive = true
    @State private var isExpanded = false
    /// The output picker (device list) — the volume slider is no longer tied
    /// to it and stays on screen whenever the panel does.
    @State private var isOutputPickerVisible = false
    @State private var isAirPlayPopoverPresented = false
    
    @State private var collapseWorkItem: DispatchWorkItem?
    @State private var parallaxResumeWorkItem: DispatchWorkItem?
    @State private var isParallaxSuspended = false
    /// Whether the pointer is resting on the panel, which holds the collapse
    /// timer off entirely rather than merely restarting it.
    @State private var isPointerInsidePanel = false
    @Default(.lockScreenGlassStyle) var lockScreenGlassStyle
    @Default(.lockScreenGlassCustomizationMode) private var glassCustomizationMode
    @Default(.lockScreenMusicLiquidGlassVariant) private var musicGlassVariant
    @Default(.lockScreenShowAppIcon) var showAppIcon
    @Default(.lockScreenPanelShowsBorder) var showPanelBorder
    @Default(.lockScreenMusicUsesEnhancedLiquidBorder) private var useEnhancedLiquidBorder
    @Default(.lockScreenPanelUsesBlur) var enableBlur
    @Default(.showMediaOutputControl) private var showMediaOutputControl
    @Default(.alwaysShowLockScreenVolume) private var alwaysShowVolume
    @Default(.showShuffleAndRepeat) private var showShuffleAndRepeat
    @Default(.musicControlSlots) private var slotConfig
    @Default(.musicSkipBehavior) private var musicSkipBehavior
    @Default(.lockScreenMusicMergedAirPlayOutput) private var mergedAirPlayOutput
    @Default(.enableLyrics) private var enableLyrics
    @Default(.lockScreenMusicAlbumParallaxEnabled) private var lockScreenParallaxEnabled
    @Default(.lockScreenMusicPanelWidth) private var collapsedPanelWidth
    @LockScreenStyle private var widgetAppearance

    init(animator: LockScreenPanelAnimator) {
        _animator = ObservedObject(wrappedValue: animator)
    }
    
    private let collapsedPanelCornerRadius: CGFloat = 28
    private let expandedPanelCornerRadius: CGFloat = 52
    private let collapsedAlbumArtCornerRadius: CGFloat = 16
    private let expandedAlbumArtCornerRadius: CGFloat = 60
    private let expandedContentSpacing: CGFloat = 28

    /// One gap between the metadata, the progress row and the transport. Even
    /// spacing beats pinning the ends: pushing title and transport apart left
    /// the whole column's slack sitting in the two gaps between them.
    private let expandedColumnSpacing: CGFloat = 18

    /// Expanded artwork fills the panel's content height rather than staying a
    /// fixed square in the middle of it. The panel grows as the volume and
    /// output rows appear, and a fixed square left a band of dead space above
    /// and below the art every time it did.
    /// The artwork is the flexible column: it takes whatever the transport row
    /// and the lyrics column do not need. Sizing it off the panel's height
    /// alone is what pushed the lyrics past the right edge -- the transport row
    /// has a hard minimum width and simply refuses to be squeezed, so the
    /// overflow came out of whatever sat beside it.
    private var expandedArtworkSize: CGFloat {
        let heightBudget = expandedBaseContentHeight + totalExtraHeight

        var widthBudget = Self.expandedSize.width + totalExtraWidth
        widthBudget -= expandedHorizontalInsets
        widthBudget -= expandedContentSpacing + minimumTransportColumnWidth
        if usesExpandedLyricsColumn {
            widthBudget -= expandedContentSpacing + expandedLyricsColumnWidth
        }

        return min(max(min(heightBudget, widthBudget), 180), 340)
    }

    /// What the transport row cannot go below: every control at its expanded
    /// size, the gaps between them, and a little either side. Measured from the
    /// slots actually on screen, since the row is user-configurable.
    private var minimumTransportColumnWidth: CGFloat {
        let count = displayedSlots.count
        guard count > 0 else { return 0 }
        let hasPlayPause = displayedSlots.contains(.playPause)
        let secondaries = CGFloat(hasPlayPause ? count - 1 : count)
        let gaps = CGFloat(count - 1) * 14
        return secondaries * controlFrameSize
            + (hasPlayPause ? playPauseFrameSize : 0)
            + gaps
            + 24
    }

    /// The leading and trailing insets `panelForeground` applies when expanded,
    /// which are 20pt a side in both presentations.
    private let expandedHorizontalInsets: CGFloat = 40

    private var expandedBaseContentHeight: CGFloat {
        Self.expandedSize.height - expandedVerticalInsets
    }

    /// What the expanded player's middle column actually needs. The panel then
    /// grows by the shortfall, if any, rather than by a fixed reserve per row:
    /// reserving for the volume and output rows on top of a height the column
    /// already had room for is what opened the gaps between everything.
    private var expandedColumnContentHeight: CGFloat {
        var height: CGFloat = 52
        height += expandedColumnSpacing + 20
        height += expandedColumnSpacing + playPauseFrameSize
        if shouldShowVolumeSlider {
            height += 14 + 13
            height += accessorySectionRawHeight
        }
        return height
    }

    /// The top and bottom insets `panelForeground` applies when expanded.
    private let expandedVerticalInsets: CGFloat = 38

    /// Expanded is the mode you open to read along, so the lyrics get a column
    /// of their own beside the player rather than a single line squeezed under
    /// the controls. The panel widens by exactly this much when it is shown.
    private let expandedLyricsColumnWidth: CGFloat = 300
    // Expanded used to be a glance at bigger artwork, and five seconds was
    // enough for that. It now holds the lyrics column, which is something you
    // sit and read, so the panel waits far longer -- and does not start
    // counting at all while the pointer is on it.
    private let collapseTimeout: TimeInterval = 30
    // Transport control sizing. Apple sizes the circular highlight at roughly
    // 2.2x the glyph so the tint reads as a comfortable ring around the symbol
    // instead of hugging it; these pairs keep that ratio in both states.
    private var controlFrameSize: CGFloat { isExpanded ? 62 : 40 }
    private var controlIconSize: CGFloat { isExpanded ? 26 : 18 }

    // Play/pause leads the row. When the secondary controls were sized up to
    // match Apple, this pair was left where it was, and the gap between them
    // closed from 1.7x to 1.35x -- enough that the row read as five buttons of
    // one size. Its glyph also sits proportionally larger in its highlight than
    // the others, which is what Apple does: the primary control is the one you
    // aim at without looking.
    private var playPauseFrameSize: CGFloat { isExpanded ? 84 : 58 }
    private var playPauseIconSize: CGFloat { isExpanded ? 39 : 28 }

    // What the volume and lyrics rows add to the panel's height. Content is
    // top-aligned, so whatever is reserved past what a row draws reads as dead
    // space along the bottom edge, and whatever falls short pins the row
    // against it.
    //
    // Collapsed, the fixed part of the panel already overruns its 180pt, so the
    // volume row has to pay for that overrun as well as for itself. Measured
    // rather than derived this time: with the row showing, the content stack
    // comes to 192.5pt, which with 16pt and 12pt insets needs 220.5pt of panel.
    //
    // 40 gave exactly 220 -- half a point short, so the capsule was not merely
    // tight against the bottom edge but clipped by it, while the transport row
    // above left roughly 33pt of air. That reads as a bar stuck to the bottom
    // of the panel, which is what it is. 48 clears the shortfall and leaves the
    // capsule about 20pt of room beneath it.
    //
    // (Earlier values: 72/88 were sized for a boxed slider with an icon and a
    // percentage label, and left obvious dead space; 32 was this arithmetic
    // done without the overrun at all.)
    //
    // The lyrics row is 8pt of inset and up to two 15pt lines, plus the same
    // 14pt gap: 52, with a little over.
    private let collapsedSliderExtraHeight: CGFloat = 48
    private let expandedSliderExtraHeight: CGFloat = 44
    private let collapsedLyricsExtraHeight: CGFloat = 56
    private let expandedLyricsExtraHeight: CGFloat = 96

    private var shouldUseFrostedBlur: Bool {
        enableBlur && !usesLiquidGlass
    }

    private var currentSize: CGSize {
        let base = isExpanded ? Self.expandedSize : collapsedPanelSize
        return CGSize(width: base.width + totalExtraWidth, height: base.height + totalExtraHeight)
    }

    /// Expanded, in the two-or-three column arrangement.
    private var usesExpandedColumnLayout: Bool { isExpanded }

    /// Whether the expanded player reads its lyrics in a side column.
    private var usesExpandedLyricsColumn: Bool {
        isExpanded && enableLyrics
    }

    private var collapsedPanelSize: CGSize {
        CGSize(width: CGFloat(collapsedPanelWidth), height: Self.collapsedHeight)
    }

    private var panelCornerRadius: CGFloat {
        isExpanded ? expandedPanelCornerRadius : collapsedPanelCornerRadius
    }

    private var usesCustomLiquidGlass: Bool {
        glassCustomizationMode == .customLiquid
    }

    private var usesStandardLiquidGlass: Bool {
        guard glassCustomizationMode == .standard else { return false }
        if #available(macOS 26.0, *) {
            return lockScreenGlassStyle == .liquid
        }
        return false
    }

    private var usesLiquidGlass: Bool {
        usesCustomLiquidGlass || usesStandardLiquidGlass
    }

    private var usesEnhancedCustomLiquidBorder: Bool {
        usesCustomLiquidGlass && useEnhancedLiquidBorder
    }

    
    var body: some View {
        if isActive && musicManager.hasActiveSession {
            panelContent
        } else {
            Color.clear
                .frame(width: collapsedPanelSize.width, height: collapsedPanelSize.height)
        }
    }
    
    private var panelContent: some View {
        ZStack(alignment: .topLeading) {
            panelBackgroundLayer
            panelForeground
        }
        .frame(width: currentSize.width, height: currentSize.height, alignment: .topLeading)
        .clipShape(RoundedRectangle(cornerRadius: panelCornerRadius, style: .continuous))
        .overlay {
            if showPanelBorder {
                panelBorderOverlay
            }
        }
        .shadow(color: Color.black.opacity(0.3), radius: 20, x: 0, y: 10)
        .contentShape(Rectangle())
        .onHover { hovering in
            isPointerInsidePanel = hovering
            if hovering {
                cancelCollapseTimer()
            } else {
                registerInteraction()
            }
        }
        .animation(.easeInOut(duration: 0.28), value: isExpanded)
        .animation(.easeInOut(duration: 0.24), value: shouldShowVolumeSlider)
        .onAppear {
            sliderValue = musicManager.elapsedTime
            isActive = true
            updatePanelSize(animated: false)
            routeManager.refreshDevices()
            if musicManager.isAppleMusicActive {
                Task { await airPlayManager.refreshDevices() }
            }
        }
        .onDisappear {
            isActive = false
            cancelCollapseTimer()
            isOutputPickerVisible = false
            parallaxResumeWorkItem?.cancel()
            parallaxResumeWorkItem = nil
            isParallaxSuspended = false
        }
        .onChange(of: isExpanded) { _, expanded in
            updatePanelSize()
        }
        .onChange(of: showMediaOutputControl) { _, enabled in
            if !enabled {
                withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
                    isOutputPickerVisible = false
                }
            }
            updatePanelSize()
        }
        .onChange(of: isOutputPickerVisible) { _, visible in
            if useMergedAirPlayOutput {
                if visible && musicManager.isAppleMusicActive {
                    Task { await airPlayManager.refreshDevices() }
                }
            }
            updatePanelSize()
        }
        .onChange(of: airPlayManager.devices) { _, _ in
            if useMergedAirPlayOutput {
                updatePanelSize()
            }
        }
        .onChange(of: routeManager.devices) { _, _ in
            if !useMergedAirPlayOutput {
                updatePanelSize()
            }
        }
        .onChange(of: enableLyrics) { _, _ in
            withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
                updatePanelSize()
            }
        }
        .scaleEffect(animator.isPresented ? 1 : 0.9, anchor: .center)
        .opacity(animator.isPresented ? 1 : 0)
        .animation(.spring(response: 0.52, dampingFraction: 0.8), value: animator.isPresented)
    }

    @ViewBuilder
    private var panelForeground: some View {
        Group {
            if isExpanded {
                expandedLayout
            } else {
                collapsedLayout
            }
        }
        .padding(.horizontal, isExpanded ? 20 : 16)
        .padding(.top, isExpanded ? 22 : 16)
        .padding(.bottom, isExpanded ? 16 : 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var collapsedLayout: some View {
        VStack(spacing: 12) {
            collapsedHeader
            progressBar
                .padding(.top, 4)
                .frame(maxWidth: .infinity)
            playbackControls(alignment: .center)
                .padding(.top, 4)
        }
    }

    private var expandedLayout: some View {
        HStack(alignment: .center, spacing: expandedContentSpacing) {
            albumArtButton(size: expandedArtworkSize, cornerRadius: expandedAlbumArtCornerRadius)
                .frame(width: expandedArtworkSize, height: expandedArtworkSize)

            VStack(alignment: .leading, spacing: expandedColumnSpacing) {
                expandedHeader
                progressBar
                    .frame(maxWidth: .infinity)
                playbackControls(alignment: .leading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)

            if usesExpandedLyricsColumn {
                expandedLyricsColumn
                    .frame(width: expandedLyricsColumnWidth)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .frame(maxHeight: .infinity, alignment: .center)
    }

    private var collapsedHeader: some View {
        HStack(alignment: .center, spacing: 16) {
            albumArtButton(size: 60, cornerRadius: collapsedAlbumArtCornerRadius)

            GeometryReader { geo in
                VStack(alignment: .leading, spacing: 1) {
                    MusicTitleMarqueeView(
                        text: musicManager.songTitle.isEmpty ? "No Music Playing" : musicManager.songTitle,
                        isExplicit: !musicManager.songTitle.isEmpty && musicManager.isCurrentTrackExplicit,
                        font: widgetAppearance.font(size: 14, weight: .semibold),
                        nsFont: .headline,
                        textColor: widgetAppearance.primary(),
                        minDuration: 0.45,
                        frameWidth: geo.size.width,
                        badgeSpacing: 5,
                        badgeLabel: "E",
                        badgeHeight: 15,
                        badgeForegroundColor: widgetAppearance.usesLightGlyphs
                            ? Color.black.opacity(0.72)
                            : Color.white.opacity(0.85),
                        badgeBackgroundColor: widgetAppearance.primary(opacity: 0.46),
                        badgeHorizontalPadding: 4,
                        badgeMinWidth: 16,
                        badgeCornerRadius: 4
                    )

                    Text(musicManager.artistName.isEmpty ? "Unknown Artist" : musicManager.artistName)
                        .font(widgetAppearance.font(size: 12, weight: .medium))
                        .foregroundColor(artistLabelColor(factor: 0.6))
                        .lineLimit(1)
                }
                .frame(width: geo.size.width, height: geo.size.height, alignment: .leading)
            }
            .frame(maxWidth: .infinity, minHeight: 36, maxHeight: 36, alignment: .leading)

            visualizer(height: 16)
        }
        .frame(height: 60)
    }

    private var expandedHeader: some View {
        HStack(alignment: .top, spacing: 16) {
            GeometryReader { geo in
                VStack(alignment: .leading, spacing: 6) {
                    MusicTitleMarqueeView(
                        text: musicManager.songTitle.isEmpty ? "No Music Playing" : musicManager.songTitle,
                        isExplicit: !musicManager.songTitle.isEmpty && musicManager.isCurrentTrackExplicit,
                        font: widgetAppearance.font(size: 21, weight: .semibold),
                        nsFont: .title2,
                        textColor: widgetAppearance.primary(),
                        minDuration: 0.55,
                        frameWidth: geo.size.width,
                        badgeSpacing: 6,
                        badgeLabel: "E",
                        badgeHeight: 18,
                        badgeForegroundColor: widgetAppearance.usesLightGlyphs
                            ? Color.black.opacity(0.74)
                            : Color.white.opacity(0.88),
                        badgeBackgroundColor: widgetAppearance.primary(opacity: 0.5),
                        badgeHorizontalPadding: 5,
                        badgeMinWidth: 19,
                        badgeCornerRadius: 5
                    )

                    Text(musicManager.artistName.isEmpty ? "Unknown Artist" : musicManager.artistName)
                        .font(widgetAppearance.font(size: 15, weight: .medium))
                        .foregroundColor(artistLabelColor(factor: 0.7))
                        .lineLimit(2)
                }
                .frame(width: geo.size.width, height: geo.size.height, alignment: .leading)
            }
            .frame(maxWidth: .infinity, minHeight: 52, maxHeight: 52, alignment: .leading)

            // Sits with the title block rather than floating off at the column's
            // far edge, and drops out entirely when the lyrics column is there --
            // two things competing for the same corner read as clutter.
            if !usesExpandedLyricsColumn {
                visualizer(height: 20)
            }
        }
    }

    private func albumArtButton(size: CGFloat, cornerRadius: CGFloat) -> some View {
        let artworkCornerRadius = resolvedArtworkCornerRadius(from: cornerRadius)

        return ZStack(alignment: .bottomTrailing) {
            albumArtImage(size: size, cornerRadius: cornerRadius)
            if showAppIcon, let icon = lockScreenAppIcon {
                let badge = appIconSize(forArtwork: size)
                icon
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: badge, height: badge)
                    .shadow(color: Color.black.opacity(0.28), radius: badge * 0.14, x: 0, y: badge * 0.06)
                    .offset(x: badge * 0.26, y: badge * 0.26)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .albumArtFlip(angle: musicManager.flipAngle)
        .parallax3D(enableOverride: lockScreenParallaxEnabled, suspended: isParallaxSuspended)
        .frame(width: size)
        .background(albumArtBackground(cornerRadius: artworkCornerRadius))
        // Deliberately no clip here. The artwork clips itself to this radius
        // and the background is already a rounded rect of it, so the only
        // thing a clip at this level did was cut the corner off the source
        // badge, which is meant to overhang.
        .opacity(musicManager.isPlaying ? 1 : 0.4)
        .scaleEffect(musicManager.isPlaying ? 1 : 0.85)
        .animation(.easeInOut(duration: 0.2), value: musicManager.isPlaying)
        .onTapGesture {
            toggleExpanded()
        }
    }

    @ViewBuilder
    private func visualizer(height: CGFloat) -> some View {
        let width = CGFloat(Defaults[.visualizerBarCount]) * 4
        if Defaults[.useMusicVisualizer] {
            Rectangle()
                .fill((Defaults[.coloredSpectrogram] ? Color(nsColor: musicManager.avgColor) : Color.gray).spectrogramGradient())
                .mask {
                    AudioVisualizerView(isPlaying: .constant(musicManager.isPlaying))
                        .frame(width: width, height: height)
                }
                .frame(width: width, height: height)
        }
    }

    private func toggleExpanded() {
        let newState = !isExpanded
        suspendParallaxInteraction()
        withAnimation(.easeInOut(duration: 0.28)) {
            isExpanded = newState
        }

        if newState {
            registerInteraction()
        } else {
            cancelCollapseTimer()
        }
    }

    private func registerInteraction() {
        cancelCollapseTimer()
        guard isExpanded else { return }
        guard !isPointerInsidePanel else { return }

        let workItem = DispatchWorkItem {
            suspendParallaxInteraction()
            withAnimation(.easeInOut(duration: 0.28)) {
                isExpanded = false
            }
        }

        collapseWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + collapseTimeout, execute: workItem)
    }

    private func suspendParallaxInteraction(for duration: TimeInterval = 0.65) {
        parallaxResumeWorkItem?.cancel()
        isParallaxSuspended = true

        let workItem = DispatchWorkItem {
            isParallaxSuspended = false
        }
        parallaxResumeWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: workItem)
    }

    private func cancelCollapseTimer() {
        collapseWorkItem?.cancel()
        collapseWorkItem = nil
    }

    private var isProgressTimelinePaused: Bool {
        !musicManager.isPlaying || musicManager.isLiveStream || musicManager.playbackRate <= 0
    }
    
    // MARK: - Progress Bar
    
    private var progressBar: some View {
        // 30fps, the rate the notch's own progress bar runs at: smooth enough
        // for a bar that moves a few points a second.
        TimelineView(
            .animation(
                minimumInterval: 1.0 / 30.0,
                paused: isProgressTimelinePaused
            )
        ) { timeline in
            MusicSliderView(
                sliderValue: $sliderValue,
                duration: Binding(
                    get: { musicManager.songDuration },
                    set: { musicManager.songDuration = $0 }
                ),
                lastDragged: $lastDragged,
                color: musicManager.avgColor,
                dragging: $dragging,
                currentDate: timeline.date,
                timestampDate: musicManager.timestampDate,
                elapsedTime: musicManager.elapsedTime,
                playbackRate: musicManager.playbackRate,
                isPlaying: musicManager.isPlaying,
                isLiveStream: musicManager.isLiveStream,
                onValueChange: { newValue in
                    registerInteraction()
                    musicManager.seek(to: newValue)
                },
                labelLayout: .inline,
                trailingLabel: .remaining,
                restingTrackHeight: 7,
                draggingTrackHeight: 11,
                tintOverride: progressSliderTint,
                desaturatesWhenIdle: true
            )
        }
        .onAppear {
            sliderValue = musicManager.elapsedTime
        }
        .onChange(of: musicManager.isLiveStream) { _, isLive in
            if isLive {
                dragging = false
                sliderValue = 0
            }
        }
    }

    private var sliderColor: Color {
        switch Defaults[.sliderColor] {
        case .white:
            return widgetAppearance.primary()
        case .albumArt:
            let base = Color(nsColor: musicManager.avgColor)
            return widgetAppearance.usesLightGlyphs
                ? base.ensureMinimumBrightness(factor: 0.6)
                : base
        case .accent:
            return .accentColor
        }
    }

    private var progressSliderTint: Color {
        sliderColor
    }

    private var brandAccentColor: Color {
        musicManager.brandAccentColor
    }
    
    // MARK: - Playback Controls
    
    private func playbackControls(alignment: Alignment) -> some View {
        // Tighter than before: the highlight circles are now wide enough that
        // Apple-sized gaps between them keep the row visually grouped.
        let spacing: CGFloat = isExpanded ? 14 : 10
        let verticalSpacing: CGFloat = (shouldShowVolumeSlider || enableLyrics) ? 14 : 10

        return VStack(spacing: verticalSpacing) {
            controlsRow(alignment: alignment, spacing: spacing)

            if shouldShowVolumeSlider {
                volumeSlider
                    .frame(maxWidth: .infinity, alignment: alignment)
                    .transition(.scale(scale: 0.98, anchor: .top).combined(with: .opacity))

                if shouldShowAirPlay {
                    airPlaySection
                        .frame(maxWidth: .infinity, alignment: alignment)
                        .transition(.scale(scale: 0.98, anchor: .top).combined(with: .opacity))
                } else if shouldShowRouteSelector {
                    mediaOutputDevicesSection
                        .frame(maxWidth: .infinity, alignment: alignment)
                        .transition(.scale(scale: 0.98, anchor: .top).combined(with: .opacity))
                }
            }

            if enableLyrics && !usesExpandedLyricsColumn {
                lyricsSection(alignment: alignment)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity, alignment: alignment)
        .padding(.top, isExpanded ? 6 : 2)
        .animation(.easeInOut(duration: 0.24), value: shouldShowVolumeSlider)
        .animation(.easeInOut(duration: 0.24), value: shouldShowAirPlay)
        .animation(.easeInOut(duration: 0.24), value: shouldShowRouteSelector)
        .animation(.easeInOut(duration: 0.24), value: enableLyrics)
    }

    private func controlsRow(alignment: Alignment, spacing: CGFloat) -> some View {
        HStack(spacing: spacing) {
            ForEach(Array(displayedSlots.enumerated()), id: \.offset) { _, slot in
                slotView(for: slot)
            }
        }
        .frame(maxWidth: .infinity, alignment: alignment)
    }
    
    private var displayedSlots: [MusicControlButton] {
        guard showShuffleAndRepeat else {
            return fallbackSlots
        }

        let normalized = slotConfig.normalized(allowingMediaOutput: showMediaOutputControl, isAppleMusicActive: musicManager.isAppleMusicActive, canFavorite: musicManager.activeSourceCanEverFavorite)
        return normalized.contains(where: { $0 != .none }) ? normalized : MusicControlButton.defaultLayout
    }

    private var fallbackSlots: [MusicControlButton] {
        switch musicSkipBehavior {
        case .track:
            return MusicControlButton.minimalLayout
        case .tenSecond:
            return [.none, .seekBackward, .playPause, .seekForward, .none]
        }
    }

    @ViewBuilder
    private func slotView(for control: MusicControlButton) -> some View {
        let seekInterval: TimeInterval = 10

        switch control {
        case .none:
            Spacer(minLength: 0)
        case .playPause:
            playPauseButton
        case .trackBackward:
            controlButton(
                icon: "backward.fill",
                size: 18,
                interaction: .none,
                symbolEffect: .replace,
                skipDirection: .backward
            ) {
                musicManager.previousTrack()
            }
        case .trackForward:
            controlButton(
                icon: "forward.fill",
                size: 18,
                interaction: .none,
                symbolEffect: .replace,
                skipDirection: .forward
            ) {
                musicManager.nextTrack()
            }
        case .seekBackward:
            controlButton(
                icon: "gobackward.10",
                size: 18,
                interaction: .wiggle(.counterClockwise),
                symbolEffect: .wiggle
            ) {
                musicManager.seek(by: -seekInterval)
            }
        case .seekForward:
            controlButton(
                icon: "goforward.10",
                size: 18,
                interaction: .wiggle(.clockwise),
                symbolEffect: .wiggle
            ) {
                musicManager.seek(by: seekInterval)
            }
        case .shuffle:
            controlButton(
                icon: "shuffle",
                size: 18,
                isActive: musicManager.isShuffled,
                activeColor: brandAccentColor
            ) {
                musicManager.toggleShuffle()
            }
        case .repeatMode:
            controlButton(
                icon: repeatIcon,
                size: 18,
                isActive: musicManager.repeatMode != .off,
                activeColor: brandAccentColor,
                symbolEffect: .replace
            ) {
                musicManager.toggleRepeat()
            }
        case .mediaOutput:
            mediaOutputControlButton
        case .airPlay:
            if useMergedAirPlayOutput {
                mediaOutputControlButton
            } else {
                standaloneAirPlayButton
            }
        case .lyrics:
            controlButton(
                icon: enableLyrics ? "quote.bubble.fill" : "quote.bubble",
                size: 18,
                isActive: enableLyrics,
                activeColor: brandAccentColor,
                symbolEffect: .replace
            ) {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                    enableLyrics.toggle()
                }
            }
        case .likeTrack:
            LikeTrackControl { presentation, toggle in
                controlButton(
                    icon: presentation.iconName,
                    size: 18,
                    isActive: presentation.isActive,
                    activeColor: brandAccentColor,
                    symbolEffect: .replace
                ) {
                    toggle()
                }
            }
        }
    }

    private var playPauseButton: some View {
        let iconName = musicManager.isPlaying ? "pause.fill" : "play.fill"

        // Shares PanelControlButton with the rest of the row so the highlight is
        // a full-size circle rather than HoverButton's undersized capsule.
        return PanelControlButton(
            glyph: .symbol(iconName),
            frameSize: playPauseFrameSize,
            iconSize: playPauseIconSize,
            iconColor: widgetAppearance.primary(),
            backgroundOpacity: 0,
            interaction: .none,
            symbolEffect: .replace
        ) {
            registerInteraction()
            musicManager.togglePlay()
        }
        .accessibilityLabel(musicManager.isPlaying ? "Pause" : "Play")
    }
    
    private func controlButton(
        icon: String,
        size: CGFloat = 18,
        isActive: Bool = false,
        activeColor: Color? = nil,
        interaction: PanelControlButton.Interaction = .none,
        symbolEffect: PanelControlButton.SymbolEffectStyle = .replace,
        skipDirection: SkipTrackGlyph.Direction? = nil,
        action: @escaping () -> Void
    ) -> some View {
        let glyph: PanelControlButton.Glyph = skipDirection.map { .skipArrows($0) } ?? .symbol(icon)
        let resolvedActiveColor = activeColor ?? brandAccentColor
        let frameSize: CGFloat = controlFrameSize
        let iconSize: CGFloat = isExpanded ? max(size, controlIconSize) : size
        let iconColor = isActive ? resolvedActiveColor : widgetAppearance.primary(opacity: 0.8)
        let backgroundOpacity: Double = isActive ? 0.22 : 0.0

        return PanelControlButton(
            glyph: glyph,
            frameSize: frameSize,
            iconSize: iconSize,
            iconColor: iconColor,
            backgroundOpacity: backgroundOpacity,
            interaction: interaction,
            symbolEffect: symbolEffect
        ) {
            registerInteraction()
            action()
        }
    }
    
    private var mediaOutputControlButton: some View {
        let frameSize: CGFloat = controlFrameSize
        let iconSize: CGFloat = controlIconSize

        return PanelControlButton(
            glyph: .symbol(mediaOutputIcon),
            frameSize: frameSize,
            iconSize: iconSize,
            iconColor: isOutputPickerOpen ? .accentColor : widgetAppearance.primary(opacity: 0.8),
            backgroundOpacity: isOutputPickerOpen ? 0.22 : 0.0,
            interaction: .none,
            symbolEffect: .replace,
            action: toggleOutputPicker
        )
        .accessibilityLabel("Media output")
    }

    private var standaloneAirPlayButton: some View {
        let frameSize: CGFloat = controlFrameSize
        let iconSize: CGFloat = controlIconSize

        return PanelControlButton(
            glyph: .symbol("airplayaudio"),
            frameSize: frameSize,
            iconSize: iconSize,
            iconColor: isAirPlayPopoverPresented ? .accentColor : widgetAppearance.primary(opacity: 0.8),
            backgroundOpacity: isAirPlayPopoverPresented ? 0.22 : 0.0,
            interaction: .none,
            symbolEffect: .replace
        ) {
            registerInteraction()
            isAirPlayPopoverPresented.toggle()
            if isAirPlayPopoverPresented {
                Task { await airPlayManager.refreshDevices() }
            }
        }
        .accessibilityLabel("AirPlay")
        .popover(isPresented: $isAirPlayPopoverPresented, arrowEdge: .bottom) {
            AirPlaySelectorPopover(
                airPlayManager: airPlayManager,
                onHoverChanged: { _ in },
                dismiss: { isAirPlayPopoverPresented = false }
            )
        }
    }

    /// The read-along column: the whole song, scrolling itself to the line
    /// being sung, with that line swept in time the same way the notch does it.
    private var expandedLyricsColumn: some View {
        HStack(spacing: 0) {
            // A hairline spine, so the column reads as its own half of the
            // panel instead of text that drifted away from the controls.
            Rectangle()
                .fill(widgetAppearance.primary(opacity: 0.12))
                .frame(width: 1)
                .padding(.vertical, 4)

            VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "quote.bubble")
                    .font(.system(size: 12, weight: .semibold))
                Text("Lyrics")
                    .font(widgetAppearance.font(size: 12, weight: .semibold))
            }
            .foregroundColor(widgetAppearance.primary(opacity: 0.55))
            .padding(.horizontal, 18)
            .padding(.top, 2)

            SyncedLyricsList(
                musicManager: musicManager,
                style: SyncedLyricsStyle(
                    fontSize: 15,
                    lineSpacing: 12,
                    horizontalPadding: 18,
                    sung: widgetAppearance.primary(),
                    unsung: widgetAppearance.primary(opacity: 0.35),
                    idle: widgetAppearance.primary(opacity: 0.35),
                    tint: widgetAppearance.primary(opacity: 0.6),
                    placeholder: "No lyrics for this track"
                )
            )
            // Fades the ends rather than cutting them, so the column reads as a
            // window onto the song instead of a box with clipped text.
            .mask(
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .black, location: 0.1),
                        .init(color: .black, location: 0.9),
                        .init(color: .clear, location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .padding(.trailing, 4)
    }

    private func lyricsSection(alignment: Alignment) -> some View {
        let line = musicManager.currentLyrics.trimmingCharacters(in: .whitespacesAndNewlines)
        let isInstrumentalBreak = musicManager.isInInstrumentalBreak
        let fontSize: CGFloat = isExpanded ? 14 : 12
        let transition: AnyTransition = .asymmetric(
            insertion: .move(edge: .bottom).combined(with: .opacity),
            removal: .move(edge: .top).combined(with: .opacity)
        )

        // Redraws while playing so the highlight tracks the music rather than
        // stepping a whole line at a time -- at 30fps, like the notch's sweep,
        // rather than at the display's full refresh rate.
        return TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !musicManager.isPlaying)) { timeline in
            let progress = musicManager.currentLyricSweepProgress(at: timeline.date)

            HStack(spacing: 8) {
                if isInstrumentalBreak {
                    // Carrying on without words, rather than nothing to show.
                    InstrumentalBreakNotes(fontSize: fontSize)
                        .lyricSweep(
                            progress: progress,
                            isCurrent: true,
                            sung: widgetAppearance.primary(opacity: 1),
                            unsung: widgetAppearance.primary(opacity: 0.45),
                            idle: widgetAppearance.primary(opacity: 0.45)
                        )
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .transition(transition)
                } else if !line.isEmpty {
                    Image(systemName: "music.note")
                        .font(.system(size: fontSize, weight: .semibold))
                        .foregroundColor(widgetAppearance.primary(opacity: 0.7))
                        .symbolRenderingMode(.monochrome)

                    Text(line)
                        .font(widgetAppearance.font(size: fontSize, weight: .semibold))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .lyricSweep(
                            progress: progress,
                            isCurrent: true,
                            sung: widgetAppearance.primary(opacity: 1),
                            unsung: widgetAppearance.primary(opacity: 0.45),
                            idle: widgetAppearance.primary(opacity: 0.88)
                        )
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.trailing, 6)
                        .id(line)
                        .transition(transition)
                }
            }
            .padding(.horizontal, isExpanded ? 10 : 8)
            .padding(.top, isExpanded ? 12 : 8)
            .frame(maxWidth: .infinity, alignment: alignment)
            .animation(.smooth(duration: 0.32), value: line)
            .animation(.smooth(duration: 0.32), value: isInstrumentalBreak)
        }
    }

    private var repeatIcon: String {
        switch musicManager.repeatMode {
        case .off: return "repeat"
        case .all: return "repeat"
        case .one: return "repeat.1"
        }
    }

    private var mediaOutputIcon: String {
        routeManager.activeDevice?.iconName ?? "speaker.wave.2"
    }

    private var volumeSlider: some View {
        // iOS draws this as a bare capsule between two speaker glyphs, with no
        // surrounding card — the panel is the card.
        VolumeCapsuleSlider(
            value: Binding(
                // Muting leaves `level` where it was, so reading it alone left
                // the capsule full and the glyph un-slashed while muted.
                get: { volumeModel.isMuted ? 0 : Double(volumeModel.level) },
                set: { newValue in
                    registerInteraction()
                    volumeModel.setVolume(Float(newValue))
                }
            ),
            tint: widgetAppearance.primary(),
            compact: !isExpanded,
            onEditingChanged: { _ in registerInteraction() }
        )
        .padding(.horizontal, isExpanded ? 6 : 4)
    }

    private var airPlaySection: some View {
        accessorySectionContainer {
            if airPlayManager.devices.isEmpty {
                Text("No AirPlay outputs available")
                    .font(.system(size: isExpanded ? 13 : 11, weight: .medium))
                    .foregroundColor(widgetAppearance.primary(opacity: 0.68))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)
            } else {
                ScrollView(.vertical, showsIndicators: true) {
                    VStack(spacing: 6) {
                        ForEach(airPlayManager.devices) { device in
                            VStack(spacing: 4) {
                                Button {
                                    registerInteraction()
                                    Task { await airPlayManager.toggleDevice(device) }
                                } label: {
                                    HStack(spacing: 8) {
                                        Image(systemName: device.iconName)
                                            .font(.system(size: isExpanded ? 14 : 12, weight: .medium))
                                            .foregroundColor(widgetAppearance.primary(opacity: 0.8))
                                        Text(device.name)
                                            .font(.system(size: isExpanded ? 13 : 11, weight: .medium))
                                            .foregroundColor(widgetAppearance.primary())
                                            .lineLimit(1)
                                        Spacer()
                                        if device.isSelected {
                                            Image(systemName: "checkmark")
                                                .font(.system(size: isExpanded ? 12 : 10, weight: .bold))
                                                .foregroundColor(.accentColor)
                                        }
                                    }
                                    .padding(.vertical, 4)
                                    .padding(.horizontal, 12)
                                }
                                .buttonStyle(.plain)

                                if device.isSelected {
                                    AirPlayVolumeSlider(
                                        airPlayManager: airPlayManager,
                                        deviceID: device.id
                                    )
                                    .padding(.horizontal, 12)
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: accessorySectionScrollMaxHeight)
            }
        }
        .padding(.vertical, 8)
    }

    private var mediaOutputDevicesSection: some View {
        accessorySectionContainer {
            if routeManager.devices.isEmpty {
                Text("No audio outputs available")
                    .font(.system(size: isExpanded ? 13 : 11, weight: .medium))
                    .foregroundColor(widgetAppearance.primary(opacity: 0.68))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)
            } else {
                ScrollView(.vertical, showsIndicators: true) {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(routeManager.devices) { device in
                            Button {
                                registerInteraction()
                                routeManager.select(device: device)
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: device.iconName)
                                        .font(.system(size: isExpanded ? 14 : 12, weight: .medium))
                                        .foregroundColor(widgetAppearance.primary(opacity: 0.82))
                                    Text(device.name)
                                        .font(.system(size: isExpanded ? 13 : 11, weight: .medium))
                                        .foregroundColor(widgetAppearance.primary())
                                        .lineLimit(1)
                                    Spacer()
                                    if device.id == routeManager.activeDeviceID {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: isExpanded ? 12 : 10, weight: .bold))
                                            .foregroundColor(.accentColor)
                                    }
                                }
                                .padding(.vertical, 5)
                                .padding(.horizontal, 12)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: accessorySectionScrollMaxHeight)
            }
        }
        .padding(.vertical, 8)
    }

    private func accessorySectionContainer<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .background(
                RoundedRectangle(cornerRadius: isExpanded ? 16 : 12, style: .continuous)
                    .fill(sliderBackgroundFill)
            )
    }

    private var sliderBackgroundFill: Color {
        widgetAppearance.primary(opacity: usesLiquidGlass ? 0.05 : 0.08)
    }

    private func artistLabelColor(factor: CGFloat) -> Color {
        if Defaults[.playerColorTinting] {
            let base = Color(nsColor: musicManager.avgColor)
            return widgetAppearance.usesLightGlyphs
                ? base.ensureMinimumBrightness(factor: factor)
                : base
        }
        return widgetAppearance.usesLightGlyphs
            ? .gray
            : Color.black.opacity(0.55)
    }

    private var useMergedAirPlayOutput: Bool {
        mergedAirPlayOutput && musicManager.isAppleMusicActive && slotConfig.contains(where: { $0 == .mediaOutput || $0 == .airPlay })
    }

    private var shouldShowAirPlay: Bool {
        // Deliberately not gated on the device list being non-empty. The merged
        // output mode owns this slot outright -- shouldShowRouteSelector stands
        // down whenever it is on -- so requiring devices left the open picker
        // rendering nothing at all, and made airPlaySection's own "No AirPlay
        // outputs available" state unreachable.
        useMergedAirPlayOutput && isOutputPickerOpen
    }

    private var shouldShowRouteSelector: Bool {
        !useMergedAirPlayOutput && isOutputPickerOpen
    }

    private var shouldShowAccessorySection: Bool {
        shouldShowAirPlay || shouldShowRouteSelector
    }

    /// Volume can sit under the transport row for as long as the panel is up,
    /// the way iOS shows it on the Lock Screen — but only when asked for.
    ///
    /// Otherwise it stays behind the output button, which is where it was.
    /// Having it always there puts the most-reached-for control one tap
    /// instead of two away, and gives the volume keys something to move while
    /// the Mac is locked, since the notch HUD has nowhere to draw there. It is
    /// also a permanent bar across a panel that is mostly artwork, which is
    /// why iOS asks first rather than assuming, and why this does too.
    private var shouldShowVolumeSlider: Bool {
        showMediaOutputControl && alwaysShowVolume
    }

    /// The device list stays behind the output button, which is what that
    /// button is for.
    private var isOutputPickerOpen: Bool {
        showMediaOutputControl && isOutputPickerVisible
    }

    private var sliderExtraHeight: CGFloat {
        sliderHeight(forExpanded: isExpanded, visible: shouldShowVolumeSlider)
    }

    private var accessorySectionScrollMaxHeight: CGFloat {
        isExpanded ? 170 : 130
    }

    private var lyricsExtraHeight: CGFloat {
        lyricsHeight(forExpanded: isExpanded, enabled: enableLyrics)
    }

    private var accessorySectionExtraHeight: CGFloat {
        // The expanded column has the room already; see expandedColumnContentHeight.
        guard !usesExpandedColumnLayout else { return 0 }
        return accessorySectionRawHeight
    }

    private var accessorySectionRawHeight: CGFloat {
        guard shouldShowAccessorySection else { return 0 }
        if shouldShowAirPlay {
            let selectedCount = airPlayManager.devices.filter(\.isSelected).count
            let totalCount = airPlayManager.devices.count
            let deviceRows: CGFloat = CGFloat(totalCount) * 30 + CGFloat(max(totalCount - 1, 0)) * 6
            let sliders: CGFloat = CGFloat(selectedCount) * 34
            return min(deviceRows + sliders + accessorySectionChrome, accessorySectionScrollMaxHeight + 16)
        }

        let totalCount = max(routeManager.devices.count, 1)
        let deviceRows: CGFloat = CGFloat(totalCount) * 30 + CGFloat(max(totalCount - 1, 0)) * 6
        return min(deviceRows + accessorySectionChrome, accessorySectionScrollMaxHeight + 16)
    }

    /// The section's own vertical padding plus the 14pt the controls stack puts
    /// above it. Leaving the stack's spacing out is what left the last device
    /// row cut in half by the panel's bottom edge.
    private var accessorySectionChrome: CGFloat { 38 }

    private var totalExtraHeight: CGFloat {
        panelAdditionalHeight(forExpanded: isExpanded)
    }

    private var totalExtraWidth: CGFloat {
        panelAdditionalWidth(forExpanded: isExpanded)
    }

    private func panelAdditionalWidth(forExpanded expanded: Bool) -> CGFloat {
        guard expanded, enableLyrics else { return 0 }
        // The column plus room for the transport row to keep its width. Adding
        // only the column's own width took that room out of the player side,
        // which the transport row will not give up -- so the lyrics were the
        // ones pushed off the edge.
        return expandedLyricsColumnWidth + 72
    }

    private func lyricsHeight(forExpanded expanded: Bool, enabled: Bool) -> CGFloat {
        guard enabled else { return 0 }
        // The side column lives inside the panel's existing height, so it must
        // not also reserve a stacked row's worth of it.
        if expanded { return 0 }
        return expanded ? expandedLyricsExtraHeight : collapsedLyricsExtraHeight
    }

    private func panelAdditionalHeight(forExpanded expanded: Bool) -> CGFloat {
        if expanded {
            return max(0, expandedColumnContentHeight - expandedBaseContentHeight)
        }
        return sliderHeight(forExpanded: expanded, visible: shouldShowVolumeSlider) +
            accessorySectionExtraHeight +
            lyricsHeight(forExpanded: expanded, enabled: enableLyrics)
    }

    private func updatePanelSize(animated: Bool = true) {
        LockScreenPanelManager.shared.updatePanelSize(
            expanded: isExpanded,
            additionalHeight: panelAdditionalHeight(forExpanded: isExpanded),
            additionalWidth: panelAdditionalWidth(forExpanded: isExpanded),
            animated: animated
        )
    }

    private var volumeIconName: String {
        if volumeModel.isMuted || volumeModel.level <= 0.001 {
            return "speaker.slash.fill"
        } else if volumeModel.level < 0.33 {
            return "speaker.wave.1.fill"
        } else if volumeModel.level < 0.66 {
            return "speaker.wave.2.fill"
        }
        return "speaker.wave.3.fill"
    }

    private var volumePercentage: String {
        "\(Int(round(volumeModel.level * 100)))%"
    }

    /// Opens or closes the output picker, refreshing the device list on the way
    /// open so the panel never shows a stale set of outputs.
    ///
    /// Closes without opening when the output control is switched off, since the
    /// picker would otherwise be left visible with no way to dismiss it.
    private func toggleOutputPicker() {
        guard showMediaOutputControl else {
            isOutputPickerVisible = false
            return
        }

        registerInteraction()
        let newState = !isOutputPickerVisible
        if newState {
            routeManager.refreshDevices()
            if useMergedAirPlayOutput {
                Task { await airPlayManager.refreshDevices() }
            }
        }

        withAnimation(.easeInOut(duration: 0.24)) {
            isOutputPickerVisible = newState
        }

        updatePanelSize()
    }

    private func sliderHeight(forExpanded expanded: Bool, visible: Bool) -> CGFloat {
        guard visible else { return 0 }
        return expanded ? expandedSliderExtraHeight : collapsedSliderExtraHeight
    }

    @ViewBuilder
    private var panelBackgroundLayer: some View {
        Group {
            if usesCustomLiquidGlass {
                customLiquidPanelBackdrop
            } else if usesStandardLiquidGlass {
                standardLiquidPanelBackdrop
            } else if shouldUseFrostedBlur {
                frostedPanelBackground
            } else {
                opaquePanelBackground
            }
        }
        .environment(\.colorScheme, widgetAppearance.materialColorScheme)
    }

    @ViewBuilder
    private var standardLiquidPanelBackdrop: some View {
        if #available(macOS 26.0, *) {
            GlassTextBackdrop(cornerRadius: panelCornerRadius)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private var customLiquidPanelBackdrop: some View {
        LiquidGlassBackground(variant: musicGlassVariant, cornerRadius: panelCornerRadius) {
            Color.white.opacity(0.04)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var frostedPanelBackground: some View {
        RoundedRectangle(cornerRadius: panelCornerRadius)
            .fill(.ultraThinMaterial)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private var opaquePanelBackground: some View {
        RoundedRectangle(cornerRadius: panelCornerRadius)
            .fill(widgetAppearance.usesLightGlyphs ? Color.black.opacity(0.45) : Color.white.opacity(0.55))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var panelBorderOverlay: some View {
        if usesEnhancedCustomLiquidBorder {
            ZStack {
                RoundedRectangle(cornerRadius: panelCornerRadius, style: .continuous)
                    .stroke(
                        Color.white.opacity(0.22),
                        lineWidth: 1.05
                    )

                RoundedRectangle(cornerRadius: panelCornerRadius, style: .continuous)
                    .inset(by: 0.85)
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.28),
                                Color.white.opacity(0.1),
                                Color.black.opacity(0.18)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.9
                    )

                RoundedRectangle(cornerRadius: panelCornerRadius, style: .continuous)
                    .inset(by: 1.55)
                    .stroke(
                        Color.black.opacity(0.16),
                        lineWidth: 0.55
                    )
            }
            .allowsHitTesting(false)
        } else if usesLiquidGlass {
            RoundedRectangle(cornerRadius: panelCornerRadius, style: .continuous)
                .stroke(
                    Color.white.opacity(usesCustomLiquidGlass ? 0.15 : 0.14),
                    lineWidth: usesCustomLiquidGlass ? 0.95 : 0.9
                )
                .allowsHitTesting(false)
        } else {
            RoundedRectangle(cornerRadius: panelCornerRadius, style: .continuous)
                .stroke(Color.white.opacity(0.35), lineWidth: 1.4)
                .allowsHitTesting(false)
        }
    }

    private func albumArtImage(size: CGFloat, cornerRadius: CGFloat) -> some View {
        Image(nsImage: musicManager.albumArt)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .compositingGroup()
            .clipShape(RoundedRectangle(cornerRadius: resolvedArtworkCornerRadius(from: cornerRadius), style: .continuous))
    }

    @ViewBuilder
    private func albumArtBackground(cornerRadius: CGFloat) -> some View {
        if usesCustomLiquidGlass {
            customLiquidAlbumArtBackground(cornerRadius: cornerRadius)
        } else if usesStandardLiquidGlass {
            if #available(macOS 26.0, *) {
                clearLiquidGlassSurface(cornerRadius: cornerRadius)
            }
        } else if shouldUseFrostedBlur {
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(.ultraThinMaterial)
        } else {
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(Color.black.opacity(0.35))
        }
    }

    private var lockScreenAppIcon: Image? {
        guard showAppIcon, !musicManager.usingAppIconForArtwork else { return nil }
        let bundleIdentifier = musicManager.bundleIdentifier ?? "com.apple.Music"
        return AppIcon(for: bundleIdentifier)
    }

    /// The source badge, sized against the artwork it sits on rather than
    /// against the panel's state.
    ///
    /// It was a flat 34pt on 60pt of collapsed artwork — over half its width —
    /// pushed a further 12pt clear of the corner, so it read as a second icon
    /// parked beside the album rather than as a mark on it. A third of the
    /// artwork, straddling the corner, is the proportion Apple uses; the clamp
    /// keeps it from growing with the expanded artwork, which is five times the
    /// size and does not want a five-times badge.
    private func appIconSize(forArtwork artworkSize: CGFloat) -> CGFloat {
        min(max(artworkSize * 0.34, 20), 54)
    }

    private func resolvedArtworkCornerRadius(from baseCornerRadius: CGFloat) -> CGFloat {
        let aspectRatio = musicManager.albumArt.size.height > 0
            ? musicManager.albumArt.size.width / musicManager.albumArt.size.height
            : 1
        return aspectRatio > 1.0 ? baseCornerRadius / 3 : baseCornerRadius
    }

    @available(macOS 26.0, *)
    private func clearLiquidGlassSurface(cornerRadius: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(.clear)
            .glassEffect(
                .clear.interactive(),
                in: .rect(cornerRadius: cornerRadius)
            )
    }

    @ViewBuilder
    private func customLiquidAlbumArtBackground(cornerRadius: CGFloat) -> some View {
        LiquidGlassBackground(variant: musicGlassVariant, cornerRadius: cornerRadius) {
            Color.clear
        }
    }
}
