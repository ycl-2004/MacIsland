import plistlib
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
ENTITLEMENTS = ROOT / "DynamicIsland" / "DynamicIsland.entitlements"
PROJECT = ROOT / "DynamicIsland.xcodeproj" / "project.pbxproj"
CI_WORKFLOW = ROOT / ".github" / "workflows" / "ci.yml"


class PrivacyConfigurationTests(unittest.TestCase):
    def test_camera_capture_is_explicitly_entitled(self):
        entitlements = plistlib.loads(ENTITLEMENTS.read_bytes())

        self.assertTrue(entitlements.get("com.apple.security.device.camera"))

    def test_automation_is_entitled_and_explained(self):
        project = PROJECT.read_text()
        entitlements = plistlib.loads(ENTITLEMENTS.read_bytes())

        self.assertNotIn("AUTOMATION_APPLE_EVENTS = NO;", project)
        self.assertTrue(entitlements.get("com.apple.security.automation.apple-events"))
        self.assertEqual(
            2,
            project.count(
                'INFOPLIST_KEY_NSAppleEventsUsageDescription = "YC Island uses Automation to control Apple Music, supported terminals, and recording controls when you use those features.";'
            ),
        )

    def test_full_access_reminder_api_has_matching_usage_text(self):
        project = PROJECT.read_text()

        self.assertEqual(
            2,
            project.count("INFOPLIST_KEY_NSRemindersFullAccessUsageDescription ="),
        )

    def test_ci_checks_the_privacy_configuration(self):
        workflow = CI_WORKFLOW.read_text()

        self.assertIn("python3 -m unittest tests.test_privacy_configuration", workflow)

    def test_current_permissions_do_not_include_removed_voice_or_legacy_eventkit(self):
        project = PROJECT.read_text()
        for key in ("NSMicrophoneUsageDescription", "NSCalendarsUsageDescription", "NSRemindersUsageDescription"):
            self.assertNotIn("INFOPLIST_KEY_" + key + " =", project)
        # System output capture is a different permission from recording a microphone.
        info = plistlib.loads((ROOT / "DynamicIsland/Info.plist").read_bytes())
        self.assertIn("NSAudioCaptureUsageDescription", info)
        self.assertIn("NSAppleMusicUsageDescription", info)

    def test_nonsandboxed_build_does_not_carry_a_sandbox_automation_exception(self):
        entitlements = plistlib.loads(ENTITLEMENTS.read_bytes())
        self.assertNotIn("com.apple.security.temporary-exception.apple-events", entitlements)
        self.assertEqual(2, PROJECT.read_text().count("ENABLE_APP_SANDBOX = NO;"))

    def test_display_brand_changes_without_resetting_existing_app_identity(self):
        project = PROJECT.read_text()
        self.assertEqual(2, project.count('INFOPLIST_KEY_CFBundleDisplayName = "YC Island";'))
        self.assertIn("PRODUCT_BUNDLE_IDENTIFIER = com.Ebullioscopic.Atoll;", project)
        self.assertIn("PRODUCT_BUNDLE_IDENTIFIER = com.Ebullioscopic.Atoll.dev;", project)


if __name__ == "__main__":
    unittest.main()
