import AppKit
import AVFoundation
import EventKit

struct FeaturePermissionSnapshot {
    var camera = AVAuthorizationStatus.notDetermined
    var events = EKAuthorizationStatus.notDetermined
    var reminders = EKAuthorizationStatus.notDetermined
    var screenRecording = false

    static func read() -> Self {
        guard !AppRuntimeEnvironment.isTesting else { return Self() }
        // Read-only checks; never request permission from the management page.
        return Self(camera: AVCaptureDevice.authorizationStatus(for: .video),
                    events: EKEventStore.authorizationStatus(for: .event),
                    reminders: EKEventStore.authorizationStatus(for: .reminder),
                    screenRecording: CGPreflightScreenCaptureAccess())
    }

    var canReadCalendar: Bool {
        [events, reminders].contains { $0 == .fullAccess || $0 == .authorized }
    }
    var cameraMessage: String? {
        switch camera {
        case .authorized: return nil
        case .notDetermined: return String(localized: "Waiting for Camera permission")
        default: return String(localized: "Camera access unavailable · open Details")
        }
    }
}
