# Micro Events

A notch tab for the user's own recurring reminders. It sits next to Home and
Shelf, and it is the only feature that pushes a reminder on its own schedule.

Updated 2026-11-10.

## What it is

One item is a title plus a repeat rule and a time:

| Repeat | Stored as | Example |
| --- | --- | --- |
| Once | exact date and time | 3 Nov, 09:00 |
| Daily | hour and minute | every day, 09:00 |
| Weekly | hour, minute and a set of weekdays | Mon + Thu, 19:30 |
| Monthly | hour, minute and a day of month | the 31st, 10:00 |

A monthly item whose day does not exist in a short month lands on that month's
last day (the 31st becomes 28 February). Recurrence is derived on demand; no
future occurrences are stored.

The one-off editor accepts a calendar date and a time. Both are saved together;
past dates and times are rejected rather than silently moved. When editing an
existing one-off, its stored time is shown in the time field. The notch time
field accepts `9`, `930`, `09:30`, `9pm` and `6:30 PM`; pressing Return formats
the time. Editing keeps the notch open until Save or Cancel.

Ticking an item completes **one occurrence**. A daily item ticked today starts
unchecked tomorrow. Completion keys are day strings (`2026-11-03`) and a
one-off uses `once`. Past keys are removed at midnight, so an item normally
carries one or two.

Both editors save through `MicroEvent.preparedForSaving(replacing:)`. A one-off
turned into a repeating rule starts today: the rule has no start date in the
editor, and keeping the one-off's date would silence it until that day.

At local midnight, completed one-offs are removed and enabled overdue one-offs
are removed after their due day. Recurring rules remain; past completion markers
are removed so the next occurrence starts unchecked. Paused one-offs are retained.
Cleanup waits for open editors. If Atoll is not running or the feature is off,
the next feature start performs any missed cleanup; activation and wake also
recheck the date. Legacy completed one-offs use the earlier of their due time
and migration time when their actual completion time was not recorded.

## Delivery

Delivery is Atoll's own closed-notch peek plus an optional chime. There is no
`UNUserNotificationCenter` call, no notification permission and no entitlement:

- Focus and Do Not Disturb filter Notification Center, not an app's own window
  or its audio, so the reminder appears regardless of Focus mode.
- Time-sensitive notifications are the only way to break through Focus through
  Notification Center, and that needs
  `com.apple.developer.usernotifications.time-sensitive`, which a personal build
  cannot rely on. Critical alerts need Apple approval. Both were rejected for
  this reason, not overlooked.
- **If Atoll is not running there is no reminder.** This is deliberate: the
  feature is for when the notch is on screen.

A delivery is skipped when it is more than 120 seconds late (for example the Mac
was asleep). Reopening the app does not replay this morning's 09:00. A missed
item still shows as due in the list and on the tab's dot.

Two cases would otherwise lose a reminder that was delivered on time:

- The closed notch cannot draw (a full-screen app, the lock screen). The notch
  view tells the manager through `isNotchHidden`; the reminder is kept and
  shown once when the notch is back, unless it was ticked off meanwhile.
- Another peek takes the notch (volume, brightness, a new track). The
  coordinator keeps the interrupted reminder and puts it back when that peek
  ends. A hide meant for another peek type does not take a reminder down.
Occurrences ticked off before delivery are excluded from the next schedule, so
they cannot repeatedly block other reminders.

The peek only draws while the notch is closed. With the notch open the tab gets
the attention dot and overdue items turn red. The dot means "something came due
today and is not ticked off": an item due tonight does not light it in the
morning. The current tab is never taken over.

## Scheduling cost

One task sleeps until the next delivery, plus one task at the next midnight so
the "today" count rolls over. With an early reminder, another task refreshes
the overdue state at the actual due time. There is no polling loop or repeating timer.
The whole schedule is recomputed on: item edits, the enable/lead settings,
display wake, system wake, clock change and time-zone change. When the feature
is off, no task exists.

## Storage

`~/Library/Application Support/Atoll/MicroEvents/events.json`

One versioned JSON document (`version: 1`). Writes are debounced 350 ms and go
through `PrivateContentFile` like Atoll's other content: atomic, folder `700`,
file `600`. No previous revision is kept, so removed items and past completion
markers do not stay on disk; the unread `events.previous.json` that earlier
builds wrote is deleted on the next save. Loading does not write unless a
legacy list had to be migrated. This is ordinary file deletion, not a guarantee
of secure erasure from filesystem snapshots or external backups.
A file that cannot be decoded is moved to `events.unreadable-<timestamp>.json`
instead of being overwritten, and the tab shows that state.
Quit and Restart wait for the latest loaded list to be written; a failed write
keeps the app open so the user can resolve the problem and retry.

This is content, so it does not live in `Defaults`, and it is not written to
EventKit: doing that would turn Micro Events into another Reminders list, add a
write permission, and hand the repeat rule to another app.

## Surfaces

- Settings → Productivity → Micro Events: the switch, the sound, the lead time
  and the list (add, edit, delete). Deletion asks for confirmation. The list
  remains available even when reminders are disabled.
- Tab: `DynamicIsland/components/MicroEvents/Views/NotchMicroEventsView.swift`.
  The list and the editor share the fixed open-notch height; the editor replaces
  the list rather than growing the window. Each event occupies one row with its
  schedule and, for what is still ahead, a countdown. Edit and delete buttons
  appear on the row under the pointer; double-clicking the event opens editing,
  and its context menu offers edit, pause/resume and delete. Delete asks for confirmation. The repeat rule is selected from a menu.
- Manager: `DynamicIsland/managers/MicroEventManager.swift`.
- Store: `DynamicIsland/components/MicroEvents/Services/MicroEventStore.swift`.
- Model and recurrence: `DynamicIsland/components/MicroEvents/Models/MicroEvent.swift`.
- Settings: `DynamicIsland/components/Settings/MicroEventSettings.swift`.
- Peek: `SneakContentType.microEvent` in `ContentView` (own surface, bypasses
  `enableSystemHUD` like music, timer and reminder).

## Limits

- Reminders need Atoll running.
- The peek is a closed-notch surface; an open notch shows the tab dot instead.
- Times are local wall-clock. A daylight-saving gap moves that day's delivery to
  the first valid time on the same day.
- No snooze, no per-item notes, no sub-steps, no ordering by hand, no sync.
  Order is unticked first, then by next occurrence.
- The tab is off by default. Each tab costs about 88 pt of minimum open width;
  `NotchHousingClearanceTests` now expects 7 standard tabs.
