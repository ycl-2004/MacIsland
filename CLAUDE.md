# Atoll

A macOS notch utility (Swift, SwiftUI + AppKit, `Defaults` for settings) that
its owner runs all day. Product name in the UI is YC Island; the bundle is
`Atoll.app`, id `com.Ebullioscopic.Atoll`.

## Direction

- **Subtract.** Prefer deleting to adding. A removal also takes its Defaults
  key, settings row, search entry, tests and docs with it.
- **Settings hold settings.** No status or diagnostic rows, no page that only
  repeats another page's switches, one home per setting.
- **No energy at rest.** Anything drawn on the notch follows the rules at the
  top of `DynamicIsland/helpers/NotchTheme.swift`. Ask before adding anything
  that keeps drawing or polling.
- **No residue.** Tests and probes leave no files and never touch the running
  app, its preferences or the user's terminals.

## Layout

- `DynamicIsland/` app: `components/` views per feature, `managers/` services,
  `models/Constants.swift` all Defaults keys, `components/Settings/` the
  Settings window (`SettingsView.swift` holds the tab enum and search index).
- `DynamicIslandTests/` unit tests, `tests/` fixture regressions, `Tools/`
  verification, `docs/` current docs, `docs/audit/<date>-<name>/` one folder
  of evidence per change.
- The project uses file-system-synchronized groups: adding or deleting a
  Swift file needs no `project.pbxproj` edit.

## Read before editing

- Notch size, position or animation: `docs/architecture.md`.
- A new notch tab: `docs/adding-a-tab.md`.
- Feature docs: `docs/micro-events.md`, `docs/extra-space.md`,
  `docs/file-convert.md`, `docs/shelf-lifecycle.md`.
- Dated files in `docs/` (`*-2026-MM-DD.md`) are records of that day, not
  current behaviour.

## Verify

```sh
python3 Tools/verify-stability.py --native-only            # build + all unit tests
python3 Tools/verify-stability.py --native-only --only-tests MicroEventTests
```

It builds a copy with its own preference domain and never launches the
installed app. Pass `--output <temp dir>` to keep the receipt out of `Build/`.
Debug builds use a `.dev` bundle id: compile checks only, never launch one
beside the installed app.

## Install

Only when the owner asks. Commit first, verify, build Release unsigned into
`Build/Release`, then follow the newest `docs/audit/*/install.py`
(`prepare`, normal quit, `install`, launch) and record the result in a new
audit folder. Keep only the newest copy in `Build/InstalledBackups`.
