# Drag approach: installation, 2026-10-19

Commit `f14f8883` opens the notch while a file drag is still just below it, so
the pointer never has to reach the top edge. Pushing a file drag into that edge
opens Mission Control's Spaces bar; the user turned off "Drag windows to top of
screen to enter Mission Control" (`enterMissionControlByTopWindowDrag = 0`) and
confirmed that setting does not cover file drags.

The zone is the closed notch widened by 60 pt on each side and deepened by
48 pt, matching the height the user found safe. Only file drags count, so
browser tab drags (web URLs) and text drags near the top don't open it.
Finder's drag session keeps mouse-dragged events from event monitors, so a
click in another app starts a 30 Hz check that ends with the press; see
`DynamicIsland/helpers/DragApproachMonitor.swift`.

## Validation before installing

- 384/384 native tests, none skipped, including
  `DragApproachMonitorTests`: only a new file drag near the notch opens it,
  once per press, and releasing the button ends the check.
- Release build from a clean tree (`BuildInfo.json`: `f14f8883`, `dirty: false`).
- After launch, a 4-second `sample` of the running app showed the main thread
  idle and no `DragApproachMonitor` frames while no button was held.

## Installation

`install.py` is the previous round's installer with this round's names: same
signing identity and designated requirement, normal quit (`quit.json`), Extra
Space unchanged, relaunch (`launch.json`), deep/strict signature check.

Kept only the newest install backup (`cleanup.json`, the `03801f15` build);
older versions can be rebuilt from git. The install helper's crash report from
its quit timeout was removed. No preferences, TCC grants or app data were changed.
