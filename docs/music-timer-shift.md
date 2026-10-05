# Music + timer shift when changing foreground applications

Date: 2026-10-05.

## Requirements (append only)

1. Diagnose the rightward shift and clipped timer in the supplied screenshots.
2. Determine a correction that keeps the existing music/timer layout stable.
3. Follow-up: implement and verify the correction; preserve the separate
   music-gesture crash fix and all unrelated worktree edits.
4. Follow-up: the installed app still shifts/clips the recording duration in
   Chrome. Audit all display paths and correct the shared positioning cause.

## Cause and measured evidence

The difference follows the foreground application's menu bar, not a Chrome
page's contents. `MenuBarLayout` measures the application menu bar through
Accessibility, and `ContentView.menuBarClearanceOffset` uses its right edge to
move the closed content right. The `.offset` applies inside the black background
and notch clip, which stay in place. The moved countdown therefore crosses the
clip's right edge.

The standalone timer emits `CenteredTimerActivityKey = true`, which disables
this offset. The music + timer branch instead renders `musicLiveActivity` and
`MusicTimerSupplementView`; it previously emitted no such preference.

Read-only measurement on the reporting Mac:

| Input | Measured value |
| --- | --- |
| Screen | 1512 × 982pt |
| Closed housing width, including existing 4pt allowance | 189pt |
| Non-hovered music artwork wing | 20pt |
| Countdown wing for `1:29:58`, bar progress | 90.253pt |
| Combined content width | 299.253pt |
| YouTube Music application menus end | 426pt |
| Chrome application menus end | 623pt |

For this non-hovered layout, the existing algorithm returns 0pt for YouTube
Music and approximately 24.626pt for Chrome. Timer settings in the local
preferences use bar progress and real-notch height, matching this calculation.
These are menu/screen measurements and a production-algorithm calculation,
not an inspection of the running app's private SwiftUI state.

Apple documents that [`offset(x:y:)`](https://developer.apple.com/documentation/swiftui/view/offset%28x%3Ay%3A%29)
changes displayed contents without changing the view's original dimensions.

## Initial correction

- The music + timer view emits the same fixed-position preference as the
  standalone timer. It no longer moves inside the notch clip when foreground
  menus change.
- `MenuBarLayout.clearanceOffset` now accepts `requiresHousingAlignment`; the
  existing housing-alignment guard lives in this tested calculation, with
  `ContentView` passing its actual visible-content state.
- Other activities retain the existing default menu-clearance behavior.

This preserves the previously working positions rather than changing wing
widths or introducing a new centre compensation. Dense application menus can
still meet the fixed HUD/background; sliding only the contents cannot solve
that collision. A different menu-conflict presentation would be separate work.

## Verification

The new regression uses the measured menu endpoints: the unprotected layout
reproduces a 24.625pt shift, and the protected layout stays at 0pt for short,
Chrome-length and longer menus. Final test/build results are recorded below.

- Debug build and 13 tests passed with zero failures: `MenuBarClearanceTests`
  (11) and `NotchWindowHostingTests` (2).
- Test result bundle: `/tmp/AtollMusicTimerShift.xcresult`.
- Test log: `/tmp/atoll-music-timer-shift-tests.log`.
- Final Release build succeeded with both the window-layout crash protection
  and this placement correction: `Build/Release/Atoll.app`.
- Release build log: `/tmp/atoll-music-timer-shift-release.log`.

## Installation — 2026-10-05

At the user's explicit request, `/Applications/Atoll.app` was replaced and
restarted at 10:31 PDT. The release app and embedded framework were signed with
the same Apple Development identity as the previous installation. The app's
bundle identifier, team and designated signing requirement match the old app.
Deep, strict signature verification passed after installation.

- Installed executable UUID: `CB81F3BC-82A8-3A9B-BBDD-B4250C301FCA`.
- Installed executable SHA-256 matches the signed staging build:
  `aa53b085ef14893169064d8a50cd8b71edd46a1c35a2f089ead159ca3330fc1c`.
- The original bundle is preserved at
  `Build/InstalledBackups/20261005-102936/Atoll.app`.
- `Build/InstalledBackups/20261005-102936/installation.json`
  records the backup, old/new hashes and launched executable path.
- The new process finished launching from `/Applications/Atoll.app`, remained
  running through the final check, and its notch window was visible.

Real music + timer foreground switching and continuous gesture track changes
remain acceptance checks; successful installation/startup alone does not verify
the intermittent crash is resolved.

## All-path follow-up — 2026-10-05

The user's recording screenshots demonstrate the same shared error in another
branch: compact recording shifts and clips in Chrome, while the desktop version
and expanded details are readable. The timer preference only protected timer
branches; it left recording and other activities exposed to the menu offset.

The correction now removes the inner menu-clearance offset for the entire
closed-content stack, plus its measured-width state and menu subscription.
No activity needs an exception or a preference to opt out. The background, clip,
shadow and contents share one position; the existing whole-surface
`notchCenterShift` still handles housing alignment. Hidden-edge and closed hover
rectangles now use that same whole-surface shift rather than application menus.
The now-obsolete timer-only preference was removed. `MenuBarLayout` remains an
optional geometry utility with no main-notch consumer or active tracker.

### Source-path audit

| Path | Coverage of the shared correction |
| --- | --- |
| Connectivity HUD and first-launch greeting | Direct children of the corrected stack |
| Charging / low / full battery, compact and standard | Same stack and shared outer surface |
| Inline volume, brightness, keyboard backlight, Bluetooth and Caps Lock | Same stack; no preference exception needed |
| Urgent and ordinary Agent activity | Both priority branches share the stack |
| Music alone; paired timer, reminder, recording, focus, Caps Lock and shelf | Every `MusicSecondaryLiveActivity` case shares the stack |
| Standalone timer and reminder, including countdown formats | Same stack; existing width reservations preserved |
| Recording compact, inline stop control and expanded details | Same `RecordingLiveActivity` branch; outer surface/clip move together |
| Downloads, focus, privacy and shelf | All remaining live-activity branches share the stack |
| Standard sneak peek, inline title strip and pinned lyrics | Same corrected content subtree |
| Open header and tabs | No application-menu offset; normal open/close layout preserved |
| Physical notch, external display and Dynamic Island pill | All use the same content stack and per-screen surface |
| Lock-screen widgets and separate panels | No `MenuBarLayout` or menu-clearance dependency found |
| Hidden-edge activation and closed hover retention | Both hit rectangles match `notchCenterShift` |

`ScreenRecordingManager` separately observes app activation to suppress expanded
controls in screen-sharing apps (Zoom, Teams, etc.). That intentional mode switch
does not measure menus or shift content; Chrome is not in that app list.

The source audit covers every branch above. It does not claim live hardware or
external-service activation of every branch. The fixed HUD can still overlap
long application menus; shifting only its contents is not a valid solution.

### Follow-up verification

- Debug build and 20 tests passed with zero failures: `ClosedHUDSizingTests`
  (8), `TimerHUDTests` (4, including rendered countdown/housing checks),
  `NotchWindowHostingTests` (2) and `MusicManagerPlaybackTests` (6).
- Result bundle: `/tmp/AtollAllActivityAlignment.xcresult`.
- Test log: `/tmp/atoll-all-activity-alignment-tests.log`.
- Release build succeeded: `/tmp/atoll-all-activity-alignment-release.log`.
- Signed with the existing identity, installed at `/Applications/Atoll.app`,
  and restarted at 10:42 PDT. Deep, strict signature verification passed.
- Current installed UUID: `F2B8A6CD-77C4-372D-B614-C33E1A62F0C2`.
- Current executable SHA-256:
  `2b8117783f33789b68badbb9f94675a687388e8f99dd6784dc1ed073457a8df6`.
- The preceding installation is preserved at
  `Build/InstalledBackups/20261005-104245/Atoll.app`; the original Sept/Oct build
  remains in the earlier backup directory.
- `Build/InstalledBackups/20261005-104245/installation.json`.
- Live observations of the installed compact recording HUD show the red badge
  and complete durations (`1:52`, `3:40`) within the surface, at consistent
  positions. The previous capture had shown a clipped duration at the right edge.
- A Chrome window was raised during the live check, but the user continued
  switching applications; subsequent frontmost-app samples were Raycast and
  Pearcleaner. A stable paired Chrome/desktop foreground capture was not
  completed, so this is not recorded as fully verified foreground-switch QA.

The all-path source audit and shared correction are complete. Live activation
of every hardware/service state and prolonged gesture-crash verification remain
outside the observed evidence above.

### Commit-scope verification

The final fix was also built from `HEAD` plus only the eight files in this
change, without the workspace's earlier refactors or resource deletions.
All 23 selected tests passed: `MenuBarClearanceTests` (11),
`NotchWindowHostingTests` (2), `MusicManagerPlaybackTests` (6) and `TimerHUDTests`
(4). Evidence: `/tmp/AtollPublishVerification.xcresult` and
`/tmp/atoll-publish-verification.log`.
