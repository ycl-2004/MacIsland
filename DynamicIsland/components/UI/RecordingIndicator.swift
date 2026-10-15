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

/// A small status light. Stop controls are available only on the open header's
/// context menu, leaving hover and primary clicks to the notch itself.
struct RecordingIndicator: View {
    @ObservedObject var recordingManager = ScreenRecordingManager.shared
    /// Only this view follows the per-second time, for its tooltip and VoiceOver value.
    @ObservedObject private var clock = ScreenRecordingManager.shared.clock
    @Default(.recordingControlMode) private var recordingControlMode
    var showsControls = true

    var body: some View {
        Group {
            if recordingManager.isRecording {
                PulsingDot(color: .systemRed, diameter: RecordingHUDLayout.dotDiameter)
                    .frame(width: showsControls ? 16 : RecordingHUDLayout.dotDiameter, height: 16)
                    .contentShape(Rectangle())
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(String(localized: "Screen Recording"))
                    .accessibilityValue(clock.formatted)
                    .accessibilityIdentifier("RecordingIndicator")
                    .help(recordingManager.stopFailureMessage ?? "\(String(localized: "Screen Recording")) · \(clock.formatted)")
                    .contextMenu {
                        if showsControls && recordingControlMode == .withStopButton
                            && !recordingManager.isScreenSharingAppActive {
                            Button(String(localized: "Stop recording")) {
                                recordingManager.stopActiveRecording()
                            }
                            .disabled(!recordingManager.canStopFromHUD)
                        }
                    }
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.notchStandard, value: recordingManager.isRecording)
    }
}

// MARK: - Preview

struct RecordingIndicator_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            // Recording state preview
            VStack {
                Text("Recording Active")
                    .font(.caption)
                RecordingIndicator()
                    .onAppear {
                        ScreenRecordingManager.shared.isRecording = true
                    }
            }
            .padding()
            .background(Color.black)
            .previewDisplayName("Recording Active")
            
            // Non-recording state preview
            VStack {
                Text("Not Recording")
                    .font(.caption)
                RecordingIndicator()
                    .onAppear {
                        ScreenRecordingManager.shared.isRecording = false
                    }
            }
            .padding()
            .background(Color.black)
            .previewDisplayName("Not Recording")
        }
    }
}
