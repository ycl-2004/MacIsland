import Defaults
import AppKit
import SwiftUI

struct FeatureManagementSettings: View {
    let navigate: (String) -> Void
    @ObservedObject private var preset = FeaturePresetController.shared
    @State private var reviewed: [FeaturePresetChange] = []
    @State private var showingPreview = false
    @State private var previewChanged = false
    @State private var resources: String?
    @State private var permissions = FeaturePermissionSnapshot()
    @State private var statsSampling = false
    @State private var codexConnected = false
    @State private var cameraRunning = false
    @State private var timerState = String(localized: "Ready · no running timer")
    @State private var textState = String(localized: "Loading…")

    var body: some View {
        Form {
            Section {
                Button("Preview lightweight suggestions") {
                    reviewed = preset.preview
                    previewChanged = false
                    showingPreview = true
                }
                .settingsHighlight(id: "features-Lightweight suggestions")
                if preset.snapshot != nil {
                    Button("Undo lightweight settings") { preset.restore() }
                }
            } header: {
                SettingsInfoLabel("Your setup", info: "Suggestions only turn off optional visuals and weather. Music, Extra Space, Agents, Timer and Shelf keep your choices. Undo keeps any settings you changed afterwards.")
            }
            Section {
                feature("Music controls", key: .showStandardMediaControls, tab: "media", note: "Play, pause and skip from the notch.")
                feature("Extra Space", key: .enableExtraSpaceFeature, tab: "extraSpace", note: "A text tab in the notch. Hiding it keeps your text.")
                feature("Agents", key: .enableAgentsFeature, tab: "agents", note: "Shows your coding agents' sessions in the notch. Screen questions need Screen Recording permission.")
                feature("Timer", key: .enableTimerFeature, tab: "timer", note: "Keeps running while the notch is closed.")
                feature("Calendar", key: .showCalendar, tab: "calendar", note: "Shows events or reminders. Allow Calendar and Reminders separately, only if you use them.")
            } header: { Text("Everyday tools") }
            Section {
                feature("Stats", key: .enableStatsFeature, tab: "stats", note: "Measures your Mac only while Stats is showing, unless background sampling is on.")
                feature("Real-time waveform", key: .enableRealTimeWaveform, tab: "media", note: "Moves the visualizer with your music. Needs audio recording permission.")
                feature("Lyrics", key: .enableLyrics, tab: "media", note: "Fetches lyrics for the current song.")
                feature("Camera mirror", key: .showMirror, tab: "appearance", note: "A camera preview when you open it. Needs Camera permission.")
                feature("Lock screen weather", key: .enableLockScreenWeatherWidget, tab: "lockScreen", note: "Refreshes the weather while your Mac is locked. Uses Location if you choose current location.")
                feature("Downloads", key: .enableDownloadListener, tab: "downloads", note: "Shows progress for files saved to your Downloads folder.")
                feature("Color Picker", key: .enableColorPickerFeature, tab: "colorPicker", note: "Picks colors from the screen. Needs Screen Recording permission.")
            } header: { Text("Optional tools") }
            Section {
                Button("Shelf settings") { navigate("shelf") }
                Button("Keyboard shortcuts") { navigate("shortcuts") }
                Button("Calendar and meeting links") { navigate("calendar") }
                Button("Hide during screenshots and recordings") { navigate("general") }
            } header: {
                SettingsInfoLabel("Quick access", info: "To reorder the notch tabs, drag their icons in the open notch.")
            }
            Section {
                if let resources { Text(resources).font(.caption).textSelection(.enabled) }
                else { Text("Reading current resource counters…").foregroundStyle(.secondary) }
                Button("Refresh resource overview") { Task { await refreshResources() } }
            } header: {
                SettingsInfoLabel("Local storage and services", info: "Counted when this page opens or when you refresh. These are cache and text sizes, not memory used by each feature.")
            }
        }
        .navigationTitle("Feature Management")
        .task { permissions = .read(); await refreshResources() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in permissions = .read() }
        .onReceive(StatsManager.shared.$isMonitoring.removeDuplicates()) { statsSampling = $0 }
        .onReceive(AgentConversationService.shared.$isLive.removeDuplicates()) { codexConnected = $0 }
        .onReceive(WebcamManager.shared.$isSessionRunning.removeDuplicates()) { cameraRunning = $0 }
        .onReceive(TimerManager.shared.$isTimerActive.combineLatest(TimerManager.shared.$isPaused).map { active, paused in
            active ? (paused ? String(localized: "Timer paused") : String(localized: "Timer running")) : String(localized: "Ready · no running timer")
        }.removeDuplicates()) { timerState = $0 }
        .onReceive(ExtraSpaceStore.shared.$isLoaded.combineLatest(ExtraSpaceStore.shared.$isDirty, ExtraSpaceStore.shared.$errorMessage).map { loaded, dirty, error in
            error != nil ? String(localized: "Save/load needs attention · open Details") : (!loaded ? String(localized: "Loading…") : (dirty ? String(localized: "Saving…") : String(localized: "Saved locally")))
        }.removeDuplicates()) { textState = $0 }
        .sheet(isPresented: $showingPreview) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Lightweight suggestions").font(.headline)
                if reviewed.isEmpty { Text("These optional features are already off.") }
                ForEach(reviewed) { change in
                    HStack { Text(preset.title(for: change.id)); Spacer(); Text("On → Off").foregroundStyle(.secondary) }
                }
                Text("Music, Extra Space, Agents, Timer and Shelf stay as configured. No content is removed.").font(.caption).foregroundStyle(.secondary)
                if previewChanged { Text("Settings changed. Review the updated list before applying.").font(.caption).foregroundStyle(.orange) }
                HStack {
                    Button("Cancel") { showingPreview = false }.keyboardShortcut(.cancelAction)
                    Spacer()
                    Button("Apply") {
                        if preset.apply(reviewed) { showingPreview = false }
                        else { reviewed = preset.preview; previewChanged = true }
                    }.disabled(reviewed.isEmpty).keyboardShortcut(.defaultAction)
                }
            }.padding(24).frame(width: 390)
        }
    }

    private func feature(_ title: String, key: Defaults.Key<Bool>, tab: String, note: String) -> some View {
        ManagedFeatureRow(title: title, key: key, note: note,
                          status: { enabled in featureStatus(tab: tab, key: key, enabled: enabled) },
                          details: { navigate(tab) })
    }

    private func featureStatus(tab: String, key: Defaults.Key<Bool>, enabled: Bool) -> String {
        guard enabled else { return String(localized: "Off") }
        switch tab {
        case "extraSpace": return textState
        case "agents": return codexConnected ? String(localized: "Codex connected · local hooks separate") : String(localized: "Codex not connected · local hooks separate")
        case "timer": return timerState
        case "stats": return statsSampling ? String(localized: "Sampling") : String(localized: "Paused until needed")
        case "appearance": return permissions.cameraMessage ?? (cameraRunning ? String(localized: "Camera preview running") : String(localized: "Camera allowed · on demand"))
        case "calendar": return permissions.canReadCalendar ? String(localized: "Read access available · refreshes when needed") : String(localized: "Waiting for read access · open Details")
        case "colorPicker": return permissions.screenRecording ? String(localized: "Screen access allowed · on demand") : String(localized: "Waiting for Screen Recording permission")
        case "downloads": return String(localized: "Enabled · folder access managed in Details")
        case "lockScreen": return String(localized: "Enabled for lock screen · location options in Details")
        default:
            if key.name == Defaults.Keys.enableRealTimeWaveform.name { return String(localized: "Enabled · audio capture checked when used") }
            return String(localized: "Enabled · follows your player")
        }
    }

    @MainActor private func refreshResources() async {
        permissions = .read()
        let thumbnails = await ThumbnailService.shared.resourceCounts()
        guard !Task.isCancelled else { return }
        func bytes(_ count: Int) -> String { ByteCountFormatter.string(fromByteCount: Int64(count), countStyle: .binary) }
        let text = ExtraSpaceStore.shared
        resources = "Extra Space: \(text.isLoaded ? bytes(text.byteCount) + " / 5 MB" : "loading")\nShelf thumbnails: \(bytes(thumbnails.bytes)) / 8 MB · \(thumbnails.running) active, \(thumbnails.queued) queued\nNetwork cache: \(bytes(URLCache.shared.currentMemoryUsage)) in memory · disk capacity \(bytes(URLCache.shared.diskCapacity))\nAgent cards: \(AgentSessionStore.shared.sessions.count) / 60 · Codex connection \(AgentConversationService.shared.isLive ? "connected" : "not connected")"
    }
}


private struct ManagedFeatureRow: View {
    let title: String
    let key: Defaults.Key<Bool>
    let note: String
    let status: (Bool) -> String
    let details: () -> Void
    @Default private var enabled: Bool

    init(title: String, key: Defaults.Key<Bool>, note: String,
         status: @escaping (Bool) -> String, details: @escaping () -> Void) {
        self.title = title; self.key = key; self.note = note
        self.status = status; self.details = details
        _enabled = Default(key)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle(isOn: $enabled) {
                SettingsInfoLabel(LocalizedStringKey(title), info: LocalizedStringKey(note))
            }
            HStack(alignment: .firstTextBaseline) {
                Text(status(enabled)).font(.caption).foregroundStyle(.secondary)
                    .accessibilityLabel("\(title) status: \(status(enabled))")
                Spacer(minLength: 8)
                Button("Details", action: details).controlSize(.small).accessibilityLabel("\(title) settings")
            }
        }.padding(.vertical, 3)
    }
}
