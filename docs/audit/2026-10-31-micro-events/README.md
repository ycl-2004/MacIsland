# Micro Events — 2026-10-31

## Goal
Add a notch tab, a sibling of Home and Shelf, holding the user's own recurring
items and reminding them at the item's time. No system notification, no
entitlement; notch and chime only.

## Added
- `components/MicroEvents/Models/MicroEvent.swift` — repeat rule and occurrences.
- `components/MicroEvents/Services/MicroEventStore.swift` — versioned JSON store.
- `components/MicroEvents/Views/NotchMicroEventsView.swift` — list and editor.
- `managers/MicroEventManager.swift` — one task to the next delivery, day boundary.
- `components/Settings/MicroEventSettings.swift` — feature settings page.
- `DynamicIslandTests/MicroEventTests.swift` — 21 tests.

## Changed
- `NotchViews.microEvents`, `ShortcutDefaultTab.microEvents`, and the tab gate in
  `NotchTabAvailability` (off by default).
- `SneakContentType.microEvent`, drawn as its own closed-notch surface.
- Coordinator tab order, width publisher and peek bypass list.
- Settings tab, search index, and the Feature Management row.
- `NotchHousingClearanceTests`: 6 → 7 standard tabs.

## Verification
| Check | Result |
| --- | --- |
| `Tools/verify-stability.py` | PASS, 408/408 native, 0 failed |
| `MicroEventTests` + `NotchHousingClearanceTests` | 23/23 |
| Release build (CI arguments) | BUILD SUCCEEDED |
| New warnings | none (one MainActor isolation warning was fixed during the work) |
| Permissions added | none |

## Behaviour worth knowing
- A tick completes one occurrence; tomorrow's copy starts unchecked.
- A delivery more than 120 s late is skipped, so reopening the app does not
  replay a past time.
- The peek renders while the notch is closed; an open notch keeps the tab dot
  instead of switching tabs.
- Disabling the feature keeps the stored items and cancels the scheduled task.

## Limits
- No reminder while Atoll is not running.
- Times are local wall-clock; a daylight-saving gap lands on the first valid
  time that day.
- No snooze, notes, sub-steps, manual ordering or sync.

## Verification-environment note
The workspace Swift language server runs `sourcekit-lsp` without a workspace or
compile database. It therefore reports `No such module 'Defaults'` and
unresolved sibling types for every file in this project, untouched files
included. A generated `compile_commands.json` plus a
`--default-workspace-type compilationDatabase` override were tried and were not
honoured by the managed server, so both were removed. The compiler remains the
authority: the module builds, and a whole-module `swift-frontend -typecheck`
using the real Xcode frontend arguments exits 0.

## Review follow-up

- Completed occurrences are skipped while choosing the next delivery, including
  an occurrence completed before an early reminder. The late-delivery search
  uses the delivery time rather than treating the lead as additional lateness.
- A one-off's chosen date and typed time are combined on save; a past date is
  rejected with an explanation. The native date picker is not limited to 14 days.
- Quit and Restart wait for Micro Events persistence and reject a failed write.
  The quit integration test saves and reloads an edit before allowing exit.
- The recurrence controls and title field now remain visible on the dark notch;
  weekday and completion controls include accessibility labels and state.
- The onboarding render test checks its frame after the asynchronous yield,
  without forcing the expected frame immediately before the assertion.

Verification after these changes: `Tools/verify-stability.py` passed all 413
native tests and its fixture checks. A subsequent targeted
`StabilityHardeningTests` run passed 18 tests, including the updated quit
integration test. The CI-argument Release build also succeeded. The native test
result includes rendered Micro Events empty,
one-off and weekly editor screenshots; these were visually inspected locally.
Some captures omit text inconsistently, including after displaying the test
window, so they cannot establish complete visual correctness. These render and
integration checks do not replace a full interactive run of the
notch, system sleep/wake, VoiceOver, or a GitHub-hosted CI run. The worktree is
uncommitted, and the pinned Xcode 26.3 CI runner has not tested these changes.

## Settings and compact-list follow-up

The Micro Events case existed but was missing from `SettingsView.availableTabs`,
so both the Productivity sidebar and Feature Management's Details destination
failed to show it. The case is now in the ordered sidebar list, with a settings
destination regression test. The settings page lists items and exposes Add,
Edit and confirmed Delete; the notch shows explicit edit and delete buttons.

The notch list uses one row per item, with Today in the schedule label and no
separate title row. Double-click opens editing; a context menu supplies Edit,
Pause/Resume and Delete. The editor uses a compact repeat selector, with an
accessible popover for Once, Daily, Weekly and Monthly.

`MicroEventTests` exercises create, reload, edit, reload, delete and reload on
an isolated store. AppKit event tests dispatch a double-click to an event row
and a click to the repeat selector, asserting the edit action and popover. UI
captures can still omit content intermittently, especially for settings, so
they are not a substitute for a full interactive user workflow. No existing
user reminder was changed by the tests.

The final local stability run passed 417 native tests and all fixture steps.
The repeat popover and double-click tests use events sent to an isolated test
window. GitHub Actions has not run against the uncommitted workspace.

The Release build was signed with the existing development identity, installed
at `/Applications/Atoll.app`, and launched successfully. Its previous app was
initially kept under `Build/InstalledBackups/MicroEventsCompact-20261031-130323-9452d4f0/`
and later removed at the user's request.
The Micro Events data file was byte-for-byte unchanged between the old app's
exit and the new app's launch. Installation evidence is under
`Build/InstallRecords/micro-events-crud-compact/`.

## Time editing and lifecycle follow-up

Editing suppresses notch auto-close and activates the editor's own window for
text entry. The time field accepts compact and AM/PM input. Rows identify the
repeat type and show overdue items in red.

The user confirmed that recurring rules remain and that a one-off overdue on
October 31 is removed at local midnight on November 1. Completed one-offs use
their completion day. App startup, activation and wake catch up on missed
cleanup. Past recurring completion markers are removed without deleting rules;
an active editor defers cleanup, and paused one-offs remain available. The
application backup is synchronized to the latest snapshot so expired records
are not retained there. Filesystem snapshots and external backups are outside
the application's control.

`Tools/verify-stability.py` passed 427 native tests and its fixture checks on
the confirmed implementation. The restart test checks both on-disk files and
preservation of the recurrence rule with isolated data. GitHub-hosted CI and a
physical overnight shutdown are separate checks; the latter was simulated by
reloading an isolated store at the next local midnight.

The confirmed Release build was signed and installed at `/Applications/Atoll.app`
after a normal app exit. The previous bundle was initially retained under
`Build/InstalledBackups/MicroEventsCompact-20261031-133123-0905a9d5/`, then
removed with all other old application backups at the user's request.
Installation evidence is in `Build/InstallRecords/micro-events-cleanup-final/`.
The replacement launched successfully from the installed path. Disposable build
and test artifacts were also cleaned; a compact local test summary remains in
`Build/CleanupReceipts/micro-events-final/`. The generated Debug and Release
application bundles were removed after verifying the installed application;
they can be rebuilt from source.

The first GitHub run on macOS 26.6.2 timed out in the synthetic time-editor
click. Its spindump showed `NSTextView.mouseDown` waiting for mouse-up while the
test attempted to send mouse-up only after mouse-down returned. The test now
queues the matching mouse-up first; this changes the test harness, not the app.
