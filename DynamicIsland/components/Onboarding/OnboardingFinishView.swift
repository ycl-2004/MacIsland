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

struct OnboardingFinishView: View {
    let onFinish: () -> Void
    let onOpenSettings: () -> Void
    var onBack: () -> Void = {}

    var body: some View {
        VStack(spacing: 24) {
            Spacer(minLength: 0)
            IslandWelcomeMark()
            VStack(spacing: 10) {
                Text("Your island is ready")
                    .font(.system(size: 30, weight: .semibold))
                    .accessibilityAddTraits(.isHeader)
                Text("Move your pointer to the notch to open YC Island.")
                    .font(.title3).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            VStack(alignment: .leading, spacing: 18) {
                OnboardingFeatureRow(icon: "cursorarrow", title: "Open the island",
                                     detail: "Use the menu bar icon to reach Settings at any time.")
                OnboardingFeatureRow(icon: "slider.horizontal.3", title: "Make it yours",
                                     detail: "Choose your tools in Feature Management. Permissions stay optional.")
                OnboardingFeatureRow(icon: "arrow.uturn.backward", title: "Come back anytime",
                                     detail: "Reopen this guide from the YC Island menu. Your settings stay as you left them.")
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 16))
            Spacer(minLength: 0)
            HStack {
                Button("Back", action: onBack)
                Spacer()
                Button("Customize in Settings", action: onOpenSettings)
                Button("Start using YC Island", action: onFinish)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
            .controlSize(.large)
        }
        .padding(.horizontal, 36)
        .padding(.bottom, 28)
    }
}

#Preview { OnboardingFinishView(onFinish: {}, onOpenSettings: {}) }
