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

struct WelcomeView: View {
    var onGetStarted: (() -> Void)? = nil
    @State private var showDataUse = false

    var body: some View {
        VStack(spacing: 24) {
            Spacer(minLength: 0)
            IslandWelcomeMark()
            VStack(spacing: 10) {
                Text("Welcome to YC Island")
                    .font(.system(size: 30, weight: .semibold))
                    .accessibilityAddTraits(.isHeader)
                Text("Your everyday tools, one island.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 18) {
                OnboardingFeatureRow(icon: "playpause.fill", title: "Stay in your flow",
                                     detail: "Music, timers and quick notes, right by the notch.")
                OnboardingFeatureRow(icon: "tray.fill", title: "Keep things close",
                                     detail: "Drop files, links and text onto Shelf for later.")
                OnboardingFeatureRow(icon: "terminal.fill", title: "Follow your agents",
                                     detail: "Check connected sessions and ask about your screen.")
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 16))
            Spacer(minLength: 0)
            VStack(spacing: 12) {
                Button("Set up YC Island") { onGetStarted?() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .keyboardShortcut(.defaultAction)
                Button("Data & permissions") { showDataUse = true }
                    .buttonStyle(.link)
                    .font(.caption)
            }
        }
        .padding(.horizontal, 36)
        .padding(.bottom, 28)
        .sheet(isPresented: $showDataUse) { OnboardingDataUseView() }
    }
}

struct IslandWelcomeMark: View {
    var body: some View {
        HStack(spacing: 18) {
            Image(systemName: "waveform").foregroundStyle(.mint)
            Text("YC").font(.system(size: 24, weight: .semibold, design: .rounded))
            Image(systemName: "terminal").foregroundStyle(.white.opacity(0.7))
        }
        .font(.system(size: 20))
        .foregroundStyle(.white)
        .padding(.horizontal, 30)
        .frame(height: 68)
        .background(.black, in: Capsule())
        .accessibilityHidden(true)
    }
}

struct OnboardingFeatureRow: View {
    let icon: String
    let title: LocalizedStringKey
    let detail: LocalizedStringKey

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 19, weight: .medium))
                .foregroundStyle(Color.effectiveAccent)
                .frame(width: 24, height: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

struct OnboardingDataUseView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Data & permissions").font(.title2.bold())
            OnboardingFeatureRow(icon: "internaldrive", title: "Stored on your Mac",
                                 detail: "Notes and Shelf data are saved locally. Camera previews and audio visualizers are processed live, without saving recordings.")
            OnboardingFeatureRow(icon: "network", title: "When data leaves your Mac",
                                 detail: "Weather and lyrics use online services. When you send a screen question, the selected image and question go to your chosen agent or provider.")
            OnboardingFeatureRow(icon: "hand.raised", title: "You choose access",
                                 detail: "Enable permissions for the features you use. You can review or revoke them in System Settings → Privacy & Security.")
            HStack {
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(28)
        .frame(width: 470)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

#Preview { WelcomeView() }
