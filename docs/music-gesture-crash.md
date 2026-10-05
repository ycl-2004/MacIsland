# Music gesture crash investigation

Date: 2026-10-05. Reported trigger: playing music, then swiping left/right on
the notch to change tracks; Atoll intermittently exits.

## Observed evidence

Four local reports have the same main-thread exception path:

- `~/Library/Logs/DiagnosticReports/Atoll-2026-09-30-055459.ips`
- `~/Library/Logs/DiagnosticReports/Atoll-2026-09-30-074902.ips`
- `~/Library/Logs/DiagnosticReports/Atoll-2026-10-02-113511.ips`
- `~/Library/Logs/DiagnosticReports/Atoll-2026-10-04-195050.ips`

The October 4 report is from `/Applications/Atoll.app`, version 1.0.0 (1637),
on macOS 27.0.1 (26A434). Its executable UUID is
`E77C3A37-7A9C-3963-9B2D-7EC84DC2C37E`, matching the installed executable.

The system log at 19:50:47 identifies `Atoll.DynamicIslandWindow`, whose frame
had grown to `{{354, -256}, {804, 1242}}`. Layout and constraint counts exceed
80 within one display cycle. The terminating exception is `NSGenericException`:

> The window has been marked as needing another Update Constraints in Window
> pass, but it has already had more Update Constraints in Window passes than
> there are views in the window.

The exception stack is:

```text
NSHostingView.windowDidLayout
  → NSHostingView.updateAnimatedWindowSize
  → NSWindow._setFrameCommon
  → NSHostingView.invalidateSafeAreaInsets
  → NSView.setNeedsUpdateConstraints
  → NSWindow._postWindowNeedsUpdateConstraints (throws)
```

This confirms a window-layout feedback loop, rather than an audio-thread crash.
The swipe path goes through `ContentView.handleSkipGesture`,
`MusicManager.handleSkipGesture`, and `NowPlayingController.nextTrack` /
`previousTrack`. Subsequent metadata changes publish artwork, title, lyrics,
and preview updates. Those animated content changes are a plausible trigger
for the loop; the crash reports do not record the specific triggering gesture.

## Change

The main notch hosting view already had `sizingOptions = []`; adding that line
again would not address the observed failure. Its production creation path now
uses `FirstMouseHostingView.makeFrameManagedContainer(size:)`: a plain `NSView`
is the window's content view, with the hosting view as an autoresizing child.
AppDelegate remains the sole owner of the window frame. Mouse handling and
SwiftUI content animations remain on the existing hosting view.

Apple documents the hosting view's content-derived constraints in
[`NSHostingView.sizingOptions`](https://developer.apple.com/documentation/swiftui/nshostingview/sizingoptions),
and the window's ownership and automatic resizing of its content view in
[`NSWindow.contentView`](https://developer.apple.com/documentation/appkit/nswindow/contentview).

## Verification

`NotchWindowHostingTests` exercises 120 overlapping animated title/lyrics/size
updates in a real AppKit panel, including content larger than the managed
window, and verifies that explicit window resizes still resize the hosting view.
This is an isolated regression fixture, not a reproduction of live music-player
gestures. Two minimal probes of the old direct-host arrangement did not reproduce
the reported crash; the exact content/animation sequence remains unconfirmed.

- Debug build and all 12 selected tests passed with zero failures:
  `NotchWindowHostingTests` (2), `MusicManagerPlaybackTests` (6), and
  `FlyoutFrameCalculatorTests` (4).
- Test result bundle: `/tmp/AtollGestureRegressionVerified.xcresult`.
- Test log: `/tmp/atoll-gesture-tests-verified.log`.
- Release build succeeded with `CODE_SIGNING_ALLOWED=NO`:
  `Build/Release/Atoll.app` (not signed for installation).
- Release build log: `/tmp/atoll-gesture-release-build.log`.

The initial source/build validation did not replace the installed application.
On 2026-10-05, the user requested replacement; the signed release with both this
protection and the music + timer placement correction is now installed and
running from `/Applications/Atoll.app`. See the
[installation evidence and backup](music-timer-shift.md#installation--2026-10-05).

Acceptance still requires continuous left/right track changes in the new build,
including track changes while lyric and artwork updates are arriving.
