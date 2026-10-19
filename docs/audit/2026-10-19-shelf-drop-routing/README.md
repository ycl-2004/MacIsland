# Shelf thumbnails and drop routing: installation, 2026-10-19

Commit `03801f15` fixes two things:

- Shelf cards sometimes showed a blank document icon instead of a thumbnail.
  A card only loaded its thumbnail once it decided it was visible, and it
  decided that against the window. The tab-switch transition slides the tab in
  from off-window by moving an ancestor, which never re-runs the card's layout,
  so the card stayed "hidden". Visibility is now measured against the row's
  scroll viewport (`ShelfRowLayout.isShowing`).
- Files dragged onto the notch open File Convert whichever tab was last
  selected. Text, links, and files while Convert is off still open Shelf; an
  open Shelf, Convert or Extra Space tab keeps its own drops.

## Validation before installing

- 383/383 native tests, none skipped, including
  `testFileDragsOpenConvertWhicheverTabWasLastAndOpenTabsKeepTheirDrops` and
  `testCardInATabStillSlidingInCountsAsShowing`.
- Release build from a clean tree (`BuildInfo.json`: `03801f15`, `dirty: false`).

## Installation

`install.py` is the previous round's installer with this round's names: same
signing identity and designated requirement, normal quit (`quit.json`), Extra
Space unchanged, relaunch (`launch.json`), deep/strict signature check.

Kept only the newest install backup (`cleanup.json`); older versions can be
rebuilt from git. The install helper's own crash reports from its quit timeout
were removed. No preferences, TCC grants or app data were changed.
