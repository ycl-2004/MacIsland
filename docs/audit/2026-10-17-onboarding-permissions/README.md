# YC Island onboarding and permissions evidence

Scope and decisions: [permission audit](../../onboarding-permissions-2026-10-17.md).

## Checks

| Check | Result | Evidence |
| --- | --- | --- |
| Debug build-for-testing | Passed | `debug-build.log`, `onboarding.steps.json` |
| Onboarding lifecycle and page renders | 6 passed | `onboarding.summary.json`, `onboarding.log` |
| Calendar/background permission regressions | 10 passed | `calendar.summary.json`, `calendar.log` |
| Feature Management navigation and settings preservation | 9 passed | `settings.summary.json`, `settings.log` |
| Media-key retry policy | 7 passed | `media-keys.summary.json`, `media-keys.log` |
| Privacy configuration | 7 passed | `privacy-configuration.log` |
| Release build | Passed | `release-build.log` |
| Plist/project parsing and diff whitespace | Passed | `plutil -lint`; `git diff --check` |

The 10 PNGs are renders of the actual SwiftUI views in an isolated native XCTest
host: three onboarding pages in English, Simplified Chinese, and Traditional
Chinese, plus the data-use sheet. The Simplified Chinese pages use dark
appearance. Windows are offscreen/inactive, so native default-action buttons
are rendered in their inactive state. Permission lists scroll; lower entries
are below the initial viewport. These are view renders, not an installed-app
interaction recording.

- [Welcome](onboarding-zh-Hans-0.png)
- [Permissions](onboarding-zh-Hans-1.png)
- [Finish](onboarding-zh-Hans-2.png)
- [Data use](data-use-zh-Hans.png)

The initial render exposed an untranslated Back button and a transparent
standalone data-use view; both were fixed before these final renders. All
recorded test runs passed. Warnings in unrelated existing code remain.

## Reproduction

```sh
python3 -m unittest tests.test_privacy_configuration
python3 Tools/verify-stability.py --native-only --only-tests OnboardingPermissionTests \
  --output /tmp/yc-island-onboarding-recheck
python3 Tools/verify-stability.py --skip-build --native-only --only-tests NextVersionReliabilityTests \
  --output /tmp/yc-island-calendar-recheck
python3 Tools/verify-stability.py --skip-build --native-only --only-tests LightweightPolicyTests \
  --output /tmp/yc-island-settings-recheck
python3 Tools/verify-stability.py --skip-build --native-only --only-tests MediaKeyTapRetryPolicyTests \
  --output /tmp/yc-island-media-keys-recheck
```

Use a fresh output directory per runner invocation. The runner copies and
ad-hoc signs a test host with a unique preference domain; it does not replace
the installed app. The full xcresult bundles remain at the paths listed in
`*.steps.json`'s companion logs and the recorded `/tmp/yc-island-*` runs.

## Boundaries

- This is a source/build audit, not an inventory of the user's granted TCC permissions.
- No system permission was granted or reset and no real agent was invoked.
- Camera/Bluetooth hardware, system Clock control, Apple Music/terminal Automation,
  protected-folder access, and signed-app system audio capture still need interactive
  validation in the relevant environment. The build uses `CODE_SIGNING_ALLOWED=NO`;
  an unsigned build cannot prove production TCC behavior.
- The initial audit did not replace the installed app. The user subsequently
  authorized replacement; it is now installed and running, verified in
  [installation.json](installation.json). Bundle IDs, signing identity and storage
  paths remain unchanged. The bundle/executable remains `Atoll`; its display name
  and updated entry points are YC Island.
- No commit, push or publication was performed.

## User-authorized installation

Installed and launched at `/Applications/Atoll.app`. The receipt verifies the
signed binary hash, deep/strict signature, exact source identity, backup hash,
and a fresh NSWorkspace running-instance check (PID 15841).

The native normal-termination monitor timed out, but a fresh independent
NSWorkspace query and process check confirmed the old app had exited. No
forced termination was used. `quit.json` records that observation. The installer
required no live old instance before moving either bundle, retained the complete
old bundle, and verified the note-file hash was unchanged by replacement.

Backup: `/Users/yichenlin/Desktop/Tester/Atoll/Build/InstalledBackups/Onboarding-20261017-202236-5967fc9d/OriginalAtoll.app`.

The app was signed with the same development identity and designated requirement
as the previous installation. No preferences or TCC grants were reset.
