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

/// Keep setup completion separate from the short notch greeting. Existing
/// installations keep their completed setup; interrupted new setups can resume.
enum OnboardingLifecycle {
    static let completionKey = "ycIslandOnboardingCompleted"

    static func shouldPresent(in defaults: UserDefaults = .standard) -> Bool {
        if let completed = defaults.object(forKey: completionKey) as? Bool {
            return !completed
        }
        return defaults.object(forKey: "firstLaunch") as? Bool ?? true
    }

    static func begin(in defaults: UserDefaults = .standard) {
        defaults.set(false, forKey: completionKey)
    }

    static func complete(in defaults: UserDefaults = .standard) {
        defaults.set(true, forKey: completionKey)
    }
}

enum OnboardingStep: Int, CaseIterable {
    case welcome, permissions, finished

    var title: LocalizedStringKey {
        switch self {
        case .welcome: "Welcome"
        case .permissions: "Your permissions"
        case .finished: "Ready to start"
        }
    }
}

struct OnboardingView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var step: OnboardingStep = .welcome
    let onFinish: () -> Void
    let onOpenSettings: () -> Void

    init(initialStep: OnboardingStep = .welcome, onFinish: @escaping () -> Void,
         onOpenSettings: @escaping () -> Void) {
        _step = State(initialValue: initialStep)
        self.onFinish = onFinish
        self.onOpenSettings = onOpenSettings
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("YC Island").font(.headline)
                Spacer()
                Text(step.title).foregroundStyle(.secondary)
                Text("\(step.rawValue + 1) / \(OnboardingStep.allCases.count)")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(Text("Setup progress"))
                    .accessibilityValue("\(step.rawValue + 1) / \(OnboardingStep.allCases.count)")
            }
            .font(.caption)
            .padding(.horizontal, 28)
            .padding(.top, 32)
            .padding(.bottom, 16)

            Group {
                switch step {
                case .welcome:
                    WelcomeView { advance(to: .permissions) }
                case .permissions:
                    PermissionsOverviewView(onContinue: { advance(to: .finished) },
                                            onBack: { advance(to: .welcome) })
                case .finished:
                    OnboardingFinishView(onFinish: onFinish, onOpenSettings: onOpenSettings,
                                         onBack: { advance(to: .permissions) })
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .id(step)
            .transition(.opacity)
        }
        .frame(width: 540, height: 640)
        .background(Color(nsColor: .windowBackgroundColor))
        .tint(.effectiveAccent)
    }

    private func advance(to next: OnboardingStep) {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) { step = next }
    }
}
