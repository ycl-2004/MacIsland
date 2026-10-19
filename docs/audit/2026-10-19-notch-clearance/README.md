# Notch clearance fix: installation, 2026-10-19

With six tabs at the old 640 pt minimum, the Convert tab sat under the camera
housing (185 pt wide on this 14" MacBook Pro), where the screen has no pixels.
Commit `d50f122f` derives the minimum open width from the housing gap and the
widest possible tab row; six tabs now get 729 pt.

- 382/382 native tests, including `NotchHousingClearanceTests`, which renders
  the full seven-tab row against the computed width.
- Release build from a clean tree (`BuildInfo.json`: `d50f122f`, `dirty: false`).
- Installed with `install.py` (the previous installer with this round's names):
  same signing identity and designated requirement, normal quit (`quit.json`),
  Extra Space unchanged, relaunch (`launch.json`), deep/strict signature check.
- On the real screen, the notch opened through the existing toggle shortcut:
  the last tab ends at about 638 pt and the housing starts at 663.5 pt.
- Kept only the newest install backup (`cleanup.json`); older versions can be
  rebuilt from git. No preferences, TCC grants or app data were changed.
