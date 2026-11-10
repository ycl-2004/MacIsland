# Settings page merge, 2026-11-10

Third step after [the review fixes](../2026-11-10-review-fixes/README.md) and
[the Settings trim](../2026-11-10-settings-trim/README.md). Commit `f2ace55a`.

The three smallest pages are folded into their neighbours; the sidebar goes
from 19 pages to 17.

- **Downloads** is a section at the end of Live Activities.
- **Color Picker** and **Extra Space** share a new **Tools** page under
  Utilities, one section each. Color Picker's four rows sit under one header;
  Extra Space's two info texts became one.
- `SettingsWindowController.showWindow(tab:)` maps `extraSpace`, `colorPicker`
  and `downloads` to the page that now holds them, next to the existing
  `fileConvert` → `shelf`. The Extra Space shortcut still lands on its switch
  when the feature is off.
- Row highlight ids keep their old prefixes (`downloads-`, `colorPicker-`,
  `extraSpace-`), so search opens the new page and scrolls to the same row.

`Tools/verify-stability.py --native-only` passed 424 native tests. The merged
pages were not opened and looked at by hand.

Release build of `f2ace55a`, `dirty: false`, same identity and designated
requirement; normal exit of the previous copy, no Atoll crash report; Micro
Events content unchanged. The backup kept is the previous copy from the
Settings trim; the older one was removed.

## Cleanup at the user's request

Later the same day the user asked for everything left over to go. Removed: the
last app backup (`Build/InstalledBackups` is now empty), the regenerable
`Build/Debug` and `Build/Release` products, `Build/codex-review-micro-events*`,
`Build/VerificationRuns`, the second cache `.build/`, and two preference files
left by earlier test runs (`app.atoll.verification.479f…` and
`com.Ebullioscopic.Atoll.dev`). The app was quit normally and left installed at
`/Applications/Atoll.app`, not running. `main` was pushed at `23c32b85`.
