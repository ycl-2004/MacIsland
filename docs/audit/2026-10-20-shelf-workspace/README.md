# Shelf file workspace — 2026-10-20

Shelf is a file workspace with three independently optional tools: **File Drop**
(the previous storage tray), **AirDrop**, and **File Convert**. One master switch
controls the tab; it does not force any module on. The user's clarification that
storage itself must be optional supersedes the initial fixed-tray assumption.

## Acceptance requirements

1. One Shelf tab replaces the separate Shelf and Convert tabs.
2. One Shelf settings page contains the master switch and all tool choices;
   settings search and Feature Management use that destination.
3. File Drop, AirDrop and File Convert are independently optional, including
   an AirDrop-only workspace. This includes the user's added requirement.
4. AirDrop keeps its square card. File Drop and conversion split the remaining
   space equally when both are on; either fills it when the other is off.
5. No tools selected is valid and offers Configure Shelf without opening on drags.
6. Disabling Shelf or File Drop retains saved entries and tool choices, pauses
   imports/thumbnail work, and cannot import into a hidden tray. Hidden saved
   items do not supply the tab badge or closed-notch activity.
7. Conversion keeps its formats, result/status display, stop/clear/Finder
   actions and original-file policy within the narrower panel.
8. Added by the user: after validation, install the new version in
   `/Applications/Atoll.app` and launch it.
9. Added by the user: remove test application copies, temporary content and
   stale system registrations after installation.

## Decisions

- Keep existing preference keys for Shelf and conversion. File Drop and AirDrop
  default to on for existing users; conversion retains its saved choice and is
  off by default. Saved tab orders safely ignore the removed `fileConvert` entry.
- AirDrop alone is centered at its existing size. No global notch-size settings
  change when choosing tools.
- Entry/icon/background drops prefer File Drop if enabled, then conversion for
  files if available. With AirDrop alone they reveal the card but reject the
  actual background drop: sending requires the explicit AirDrop card.
- Keep original is in the conversion panel's options menu and in Shelf settings.
  Formats scroll horizontally, and original-file result notes can wrap.
- Preserve the established dark native UI and existing storage/conversion services.

## Evidence

- Native render probe: `Build/VerificationRuns/shelf-workspace-20261020-render/`.
  One diagnostic test passed, generating all eight tool combinations, a loaded
  panel, a real PNG-to-JPEG result, and the grouped Shelf settings page. All
  eight layouts were visually inspected at 640 × 150 pt; settings at 600 × 900 pt.
- The archived [render probe](ShelfWorkspaceRenderProbeTests.swift) was temporarily
  placed in `DynamicIslandTests/` to run, then moved here so it does not become a
  permanent screenshot-writing unit test.
- [All tools](all-tools.png), [AirDrop only](airdrop-only.png),
  [no tools](no-tools.png), [loaded](loaded.png), [converted](converted.png),
  [settings](settings.png).
- The first full run passed 387 tests but failed the diagnostic render probe:
  its standalone settings view lacked `SettingsHighlightCoordinator`. Correcting
  the probe's environment resolved the failure; product settings already supply it.
- Final native suite: 387 passed, zero failed/skipped, in
  `Build/VerificationRuns/shelf-workspace-20261020-final/`; Debug build passed.
- Python configuration/lifecycle checks: 10 passed.
- Verification uses the existing unique-domain copied-host runner. The installed
  app's preferences and saved Shelf content were not edited by the tests.

## Installation and cleanup

The user's added installation/cleanup request was completed after validation:

- Release build passed. `/Applications/Atoll.app` was signed with the existing
  signing identity and verified against the current source SHA-256
  `255cdc7c5fdf4105e6c6822356b184d25819bebef86f22bba73a341cf0628f3b`.
- The previous app exited normally with PID exit confirmation. The new app
  finished launching as PID 59985 from `/Applications/Atoll.app`.
- Shelf `items.json` and Extra Space content hashes were unchanged by installation.
- [Cleanup receipt](cleanup.json): 11 generated paths removed (1121.5 MiB),
  including Debug/Release products, the failed test host, raw result bundles,
  test launch configuration, render fixtures and helper/cache. Source, compact
  validation logs and the screenshots above are retained.
- Both raw rollback app bundles were verified inside zip archives before removal,
  so they cannot be rediscovered as extra applications. The current rollback
  archive is in `Build/InstalledBackups/ShelfWorkspace-20261020-090215-26df3b87/`.
- Eight duplicate/stale application registrations were unregistered. No generated
  app bundles remain under `Build`; no production preferences/content, TCC database
  or global registration settings were reset.
- See [installation](installation.json), [normal quit](quit.json),
  [launch](launch.json), and [final validation](validation.json) for receipts.

The layout uses SwiftUI stacks and bounded drop regions. Apple documents that a
drop destination follows the receiving view's size and position:
[onDrop(of:isTargeted:perform:)](https://developer.apple.com/documentation/swiftui/view/ondrop(of:istargeted:perform:)-f15m).
The explicit per-panel handlers preserve that distinction within the shared tab.

## Validation boundary

These are native service/routing tests and offscreen render captures. They do not
certify a new recipient-side AirDrop transfer or a Finder drag into the installed
app. No recipient-side AirDrop transfer was sent. No commit, push or publish
was performed.
