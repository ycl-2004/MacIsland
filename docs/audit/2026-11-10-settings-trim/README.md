# Settings trim, 2026-11-10

Follow-up to [the review fixes](../2026-11-10-review-fixes/README.md), at the
user's request: keep only settings that mean something. Commit `7bf58fb7`.

## Removed

- **Feature Management.** Its 14 switches each exist on the feature's own
  page, and every page is always in the sidebar. The lightweight preset
  (`FeaturePresetController`, never used on this Mac: no undo snapshot was
  stored), the quick links and the resource counters went with it, as did
  `FeaturePermissionSnapshot`. The empty-notch button and the end of
  onboarding open Settings instead.
- **Status and diagnostics.** Stats live data and Start/Stop/Clear; the three
  battery HUD test buttons; Copy Latest Crash Report (it looked for
  `DynamicIsland*.crash`, which this app never writes); Color Picker status
  and quick actions (the picker panel has the same actions); the recording,
  Focus, camera and microphone status rows; Shelf item count and data folder
  button; Extra Space size and file reveal; the File Convert format list.
- The Stats page marked itself as a visible Stats surface to feed its live
  rows, so merely opening it started sampling. It no longer does.

## Kept on purpose

- File Convert's optional engines: it is the only place that says whether
  LibreOffice and FFmpeg were found.
- Agents' connection row and Install/Remove: Remove is undone by Install, so
  it gets no confirmation.
- The Controls page's appearance rows stay live with volume and brightness
  off: the same bar draws Bluetooth and battery peeks.
- `BatteryStatusViewModel`'s level and low-power overrides are now only called
  with their defaults; they were left in place rather than rewired.

## Added

- A confirmation before removing a custom icon and before resetting the timer
  sound. Both delete Atoll's copy of the file.
- 33 search entries for rows that could not be found, and the Downloads page,
  which search had skipped since the first commit.

## Verification and installation

`Tools/verify-stability.py --native-only` passed 424 native tests (five tests
of the removed preset and permission snapshot went with them). The pages were
not opened and clicked through by hand after the change.

Release build of `7bf58fb7`, `dirty: false`, same signing identity and
designated requirement. Normal exit of the previous copy, no Atoll crash
report. When the previous copy quit it saved the Micro Events list through the
new writer: the folder is `700`, the file `600`, `events.previous.json` is
gone, and the content is unchanged. Records are next to this file.
