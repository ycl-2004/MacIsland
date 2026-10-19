/*
 * Atoll (DynamicIsland)
 * Copyright (C) 2024-2026 Atoll Contributors
 *
 * Originally from boring.notch project
 * Modified and adapted for Atoll (DynamicIsland)
 * See NOTICE for details.
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
import EventKit

/// An explanation, not a batch permission request. Actual requests stay beside
/// the feature the person chooses to use.
struct PermissionsOverviewView: View {
    let onContinue: () -> Void
    let onBack: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Start with what you need")
                    .font(.system(size: 26, weight: .semibold))
                    .accessibilityAddTraits(.isHeader)
                Text("Notes, timers and Shelf text or links work without these permissions. Everything below is optional.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    OnboardingFeatureRow(icon: "accessibility", title: "Accessibility",
                                         detail: "For media-key controls, system Clock timers and detecting full-screen apps.")
                    OnboardingFeatureRow(icon: "camera", title: "Camera",
                                         detail: "Only for the live mirror. Leave off if you do not use it.")
                    OnboardingFeatureRow(icon: "calendar", title: "Calendar & Reminders",
                                         detail: "Choose either separately in Calendar settings. View events or view and complete reminders.")
                    OnboardingFeatureRow(icon: "rectangle.dashed", title: "Screen & system audio",
                                         detail: "Screen access is for screen questions and color picking. Audio capture is for live waveforms and per-app volume, not microphone recording.")
                    OnboardingFeatureRow(icon: "folder", title: "Files & Folders",
                                         detail: "Only the files you add to Shelf and folders used by Downloads. Shelf does not require Full Disk Access.")
                    OnboardingFeatureRow(icon: "location", title: "Location & Bluetooth",
                                         detail: "For local weather and Bluetooth device status. Leave off when you do not use these features.")
                    OnboardingFeatureRow(icon: "music.note", title: "Automation & Apple Music",
                                         detail: "Automation controls Music or supported terminals. Apple Music access is only for animated artwork.")
                    Divider()
                    OnboardingFeatureRow(icon: "lock.shield", title: "Usually leave off",
                                         detail: "Full Disk Access is only for custom Focus details. Developer Tools is only for the optional advanced Focus detection mode.")
                }
                .padding(.vertical, 8)
                .padding(.trailing, 12)
            }
            Divider()
            HStack {
                Button("Back", action: onBack)
                Spacer()
                Button("Continue", action: onContinue)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
            .controlSize(.large)
        }
        .padding(.horizontal, 36)
        .padding(.bottom, 28)
    }
}

/// Independent EventKit requests; opening this view never prompts for access.
struct CalendarPermissionControls: View {
    @ObservedObject private var manager = CalendarManager.shared
    @State private var isRequesting = false

    var body: some View {
        Section {
            permissionRow(title: "Calendars", status: manager.calendarAuthorizationStatus,
                          pane: "Privacy_Calendars", request: { await manager.checkCalendarAuthorization() })
            permissionRow(title: "Reminders", status: manager.reminderAuthorizationStatus,
                          pane: "Privacy_Reminders", request: { await manager.checkReminderAuthorization() })
        } header: {
            Text("Permissions")
        } footer: {
            Text("Calendar and Reminders access are separate. Allow only what you want to display.")
        }
    }

    private func permissionRow(title: LocalizedStringKey, status: EKAuthorizationStatus,
                               pane: String, request: @escaping () async -> Void) -> some View {
        HStack {
            Text(title)
            Spacer()
            if status == .fullAccess || status == .authorized {
                Label("Allowed", systemImage: "checkmark.circle")
                    .foregroundStyle(.secondary)
            } else if status == .notDetermined || status == .writeOnly {
                Button("Allow Access") {
                    isRequesting = true
                    Task { @MainActor in
                        defer { isRequesting = false }
                        await request()
                    }
                }
                .disabled(isRequesting)
            } else {
                Text(status == .restricted ? "Restricted" : "Denied").foregroundStyle(.secondary)
                Button("Open System Settings") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
        }
    }
}
