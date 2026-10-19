# File Convert: installation and cleanup, 2026-10-19

User-authorized replacement of `/Applications/Atoll.app` with commit `782898e4`
(File Convert), followed by removal of earlier test and install leftovers.
See [File Convert](../../file-convert.md) for the feature itself.

## Validation before installing

- 380/380 native tests, including 15 File Convert tests. The LibreOffice and
  FFmpeg conversions ran for real on this Mac; none were skipped.
- Release build from a clean tree; `BuildInfo.json` records commit `782898e4`,
  `dirty: false`, source SHA-256 `1fc39edf…25def`.
- Python configuration tests passed.

## Installation

`install.py` is the previous round's installer with this round's names.
`prepare` signed the Release build with the existing certificate and team and
confirmed the designated requirement matches the installed app, so existing
macOS permissions still apply. The running app was quit normally
(`quit.json`): the helper's observer timed out as last time, an independent
check found no process, and no crash report was written. `install` verified
hashes and signatures, moved the old app to the backup below, and confirmed
Extra Space content was unchanged. The app relaunched (`launch.json`) and
passed `codesign --verify --deep --strict`.

While the app was not running, `enableFileConvertFeature` was set to true in
`com.Ebullioscopic.Atoll` so the Convert tab is available right away. It can be
turned off in Feature Management. No other preference or TCC grant changed.

Backup: `Build/InstalledBackups/FileConvert-20261019-111047-07d8dfe0/OriginalAtoll.app`.

## Cleanup

`cleanup.py` ran as a dry run (`cleanup-plan.json`), then applied (`cleanup.json`):

- Unregistered 13 stale app records: an old backup in `/Applications/.Atoll-backups`,
  copies already deleted from the Trash, `/private/tmp` and an old session
  folder, and the current Debug/Release builds.
- Removed 181.7 MB: the September backup inside `/Applications`, the two older
  install backups, an empty staging folder, one leftover test-host preference
  file, the Debug build's preference file, and 35 `AtollTests-*` test content
  folders.
- Kept: the installed app, its preference domain and app data, the newest
  backup, and the build products.

Afterwards only `/Applications/Atoll.app` is registered as an installed copy.
macOS re-registered the Debug build and its UI-test runner on its own, as it
does for any app bundle in a user folder; new builds do the same. They don't
add menu-bar or permission entries unless launched directly.

The test content folders came from `AppRuntimeEnvironment.testDirectory`, which
nothing removed. `Tools/verify-stability.py` now deletes the folders each run
creates, alongside the test host it already removed.

TCC databases were not read or edited, and Launch Services and Control Center
were not reset.
