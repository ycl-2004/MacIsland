# NetEase clears Now Playing while it plays, 2026-11-16

The owner reported that with NetEase Cloud Music playing, the music activity
showed on the notch for about a second and then went away, and later came back
without anything having been changed.

Commit `beab19ff`. NetEase Cloud Music 3.1.14 (3459), macOS 27.2.1.

## What was wrong

NetEase clears its own Now Playing info a few seconds after it launches and
resumes a song. The song keeps playing. Atoll believed the clear, so the title
went empty and the activity was hidden until NetEase published again.

Caught live at about 19:46: NetEase held the power assertion "NetEase
CloudMusic is playing music" for two minutes while the adapter's `get`
returned `null`. The unified log (`/usr/bin/log show`, processes
`mediaremoted` and `NeteaseMusic`) for that launch:

```
19:44:53      NeteaseMusic pid 66867 starts
19:44:54.573  mediaremoted  163music setting playback state from <Paused> to <Playing>
19:44:56.345  mediaremoted  163music setting playback state from <Playing> to <Stopped>
19:44:58.142  NeteaseMusic  Setting nowPlayingInfo with mergePolicy Replace: <private>
19:44:58.159  NeteaseMusic  AudioQueueObject: New output
19:44:58.191  mediaremoted  163music setting playback state from <Stopped> to <Playing>
19:44:58.613  mediaremoted  163music setting playback state from <Playing> to <Unknown>
19:44:58.656  NeteaseMusic  Setting nowPlayingInfo with mergePolicy Replace: NULL
19:44:58.657  NeteaseMusic  Clearing nowPlayingInfo
19:47:01.767  mediaremoted  163music setting playbackQueue (next track; first publish since)
```

The clear is logged by the NetEase process itself. No command to NetEase
appears in `mediaremoted`'s log in that window.

The same Playing, Unknown, `Replace: NULL` sequence followed all three launches
in the log: 19:44:03 (pid 66745), 19:44:54 (pid 66867) and 19:53:31
(pid 68304), the clear landing 0.4 to 2.2 s after playback started. On the
third the resumed song ended 1.3 s in, so the next track was published 0.7 s
after the clear and nothing stayed hidden. A track change without a launch
(19:50:03, 19:57:01) has no clear.

The adapter reports the clear as `{"diff":false,"payload":{}}`.

## What changed

`NowPlayingController` does not apply a clear from NetEase while NetEase is
still running. It keeps the last state, playing or paused as it was, and holds
the clear back. The next update of any kind replaces the kept state. If NetEase
quits first (`NSWorkspace.didTerminateApplicationNotification`), the clear is
applied. Every other player's clear is applied as before. Nothing polls.

## Checked

- `Tools/verify-stability.py --native-only` on the committed source: 431
  tests, 0 failures, including the seven in `NowPlayingClearTests`, which feed
  the controller the recorded adapter lines.
- Release build of `beab19ff`, `dirty: false`, same identity and designated
  requirement; Shelf and Extra Space content unchanged; no Atoll crash report;
  launched as pid 72438.

## Installation

The first quit ended the running copy (pid 1474) normally: its log has
"Termination complete" at 20:06:12.795 and launchd removed it at 20:06:12.827.
`Build/InstallTools/ShelfFix-app-lifecycle` still waited its full 30 s and
reported that termination had not finished, so nothing was installed, and the
launch step that followed it started the old copy again as pid 72030. That
binary was built on 2026-10-17 from the `AppLifecycle.swift` of that day, which
waits on `NSRunningApplication.isTerminated`; the 2026-10-20 source checks the
pid instead.

The quit and launch on record were made with the 2026-10-20 source compiled
outside the repository. `quit.json` is the exit of pid 72030;
`previousInstance` in `installation.json` is pid 1474, from `prepare`. The
binary in `Build/InstallTools` was left as it is and still answers `status`
for `install.py`.

## Not checked

- The installed copy has not yet been seen through a NetEase launch.
- A pause while the info is cleared. In the one recording made for it NetEase
  had already published again. In its normal state NetEase publishes on every
  pause and resume (19:53:59, 19:54:12, 19:55:15, 19:56:18), and at 19:47:01
  it published from the cleared state, so a pause is expected to end the kept
  state. If it does not, the notch shows the song as playing until NetEase
  next publishes or quits.

## Still open

- In the cleared state NetEase had not yet published the resumed song's
  position, and on the third launch the first publish had no duration either.
  The kept song then has title, artist and artwork, but its progress and
  lyric timing start from zero until the next track.
- CoreAudio's `kAudioProcessPropertyIsRunningOutput` for NetEase was looked at
  as an independent "still playing" signal and not used: a listener block on
  it never fired across five changes a 0.2 s poll saw, and it turns false
  about 8 s after a pause (19:53:59.3 to 19:54:07.2, 19:55:16.0 to 19:55:23.8).
