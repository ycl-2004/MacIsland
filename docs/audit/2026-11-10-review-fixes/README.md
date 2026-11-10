# Review fixes, 2026-11-10

A check of the running app, its log, the Micro Events feature and the Settings
window, followed by the fixes below. Commits `0d69c75f` and `6beac1b7`.

## What was checked

- The unified log of the running app (one hour, pid 917): no crash report; all
  68 error lines fell in the launch minute and came from system camera, audio
  and Bluetooth probing.
- Micro Events model, store, manager, tab and settings page, by reading.
- Every Settings tab, for stale reads, missing parent/child gating, duplicated
  rows and unread keys. All 254 `Defaults` keys were grepped for a reader.

## What changed

Micro Events
- A one-off turned into a repeating rule starts today; both editors save
  through `MicroEvent.preparedForSaving(replacing:)`.
- The list is written through `PrivateContentFile` (file 600, folder 700). The
  second copy `events.previous.json`, which nothing read, is gone and is
  deleted on the next save. Loading no longer rewrites the file.
- A reminder that comes due while the closed notch cannot draw is shown when
  the notch is back. One interrupted by another peek returns afterwards.
- The tab dot lights once an item has come due, not from midnight.
- Type one step larger. Edit and delete appear on the hovered row. The row no
  longer says "Today ·" or "Overdue".
- The settings page keeps the switches and the list; the status rows went.

Settings
- Caps Lock rows, the HUD colour row and the Ask About Screen recorder follow
  their parent switch as it changes.
- Calendar list options, the three battery HUD switches and the closed-notch
  width slider are disabled while their parent switch is off.
- Music live activity lives in Media, reminder live activity in Calendar, the
  display style picker in General, the Extra Space shortcut in Shortcuts.
- Removed: the unread `recordingHoverStyle` key, 33 unused bindings, a second
  copy of the lock-screen glass rule, the unused edit panel.

The user's own setting `showDoNotDisturbLabel` was switched off with
`defaults write` after installation, as agreed in the review.

## Verification

`Tools/verify-stability.py --native-only` passed 429 native tests on the
committed tree. The time-editor test used to depend on which tests ran before
it: AppKit's first text check on resigning focus can wait on a slower system
thread, and XCTest records that wait as a failure. The test now switches text
checking off for its field; the app is unchanged by that.

Not exercised by hand: the hidden-notch replay and the interrupted-peek
return. Both are covered by reading only, not by a test or a live reminder.

## Installation

Release build of `6beac1b7`, `dirty: false`, signed with the existing identity;
designated requirement matched the installed copy. The old app exited normally
(the helper's observer timed out with 133 as usual; no Atoll crash report).
`events.json` had the same content before the quit and after the new launch,
and the new app did not rewrite it at launch. Records: `installation.json`,
`quit.json`, `launch.json`, `cleanup.json`.

## Left for a decision

Settings sections that show status rather than settings, tabs with one or two
rows, the Features hub that repeats 14 master switches, search entries missing
for about thirty rows, and destructive buttons without confirmation. None of
these were changed.
