# Adding a notch tab

Updated 2026-10-31. This is the order the code actually resolves a tab in.
Read [the sizing rules](architecture.md#before-changing-notch-geometry) first:
a tab is geometry, not only a view.

## 0. Decide whether it is a tab at all

A tab is a top-level surface in the header and in the open notch. A panel
inside an existing tab is cheaper in every sense. File Convert is the worked
example: it began as `NotchViews.fileConvert`, then became a panel inside Shelf
because it shares the same files, the same drop area and the same settings page.
Adding that panel changed no tab width and no tab-switch size.

If the feature only refines an existing workspace, add a panel and a switch.
Only add a tab when it deserves its own icon in the header.

## 1. Declare the case

`DynamicIsland/enums/generic.swift`

- Add the case to `NotchViews`.
- If the global shortcut should reach the tab, add a `ShortcutDefaultTab` case
  and its `targetNotchView` mapping. "Last Active" stays nil by design.

The saved order stores `String(describing:)` of the case. Renaming a case
silently drops its saved position; the removed `fileConvert` entry is ignored
by `SavedRowOrder.apply`, which is the intended behaviour.

## 2. Make it available

`DynamicIsland/helpers/NotchTabAvailability.swift`

- Add an `init` parameter and a `candidates` entry. The order in `candidates`
  is the default order; the user's saved order overrides it.
- Add the gate in `static var current`. Keep it cheap and side-effect free:
  this runs from the header, content, coordinator and minimum-width code.

`resolve(_:)` returns the first enabled tab for any disabled, remembered or
shortcut target. Home is special: when no standard tab is enabled, `tabs` is
empty, `resolve` returns `.home`, and `ContentView` renders Feature Management
access instead of hidden feature content.

## 3. Add the preference

`DynamicIsland/models/Constants.swift`, in `extension Defaults.Keys`

- Add `enableXFeature = Key<Bool>("enableXFeature", default: false)`. New
  surfaces default off. Pick a name that says what it enables, and keep the
  key stable once shipped.

## 4. Teach the coordinator

`DynamicIsland/DynamicIslandViewCoordinator.swift`

- Add the case to `tabOrder` (used only for slide direction).
- Add `Defaults.publisher(.enableXFeature)` to the `MergeMany` that calls
  `ensureValidSelection()` and `enforceMinimumNotchWidth()`.

## 5. Size it

`DynamicIsland/sizing/matters.swift`

- Normally nothing to edit: `openNotchSize` calls
  `currentRecommendedMinimumNotchWidth()`, which derives from
  `enabledStandardTabCount()` and `NotchTabAvailability.current`.
- Each extra tab costs two tab slots in that budget, about 88 pt at the
  current constants, before the 640 pt floor. The width is also clamped to the
  screen by `maxAllowedNotchWidth()`.
- If the tab changes the Home surface instead, check `homeRequiredNotchWidth()`.

## 6. Render it

`DynamicIsland/ContentView.swift`

- Add the `switch coordinator.currentView` case that mounts the tab's root
  view, next to the existing `.shelf`, `.timer`, `.stats` cases.
- Keep the view inside the existing notch surface. Do not add another window
  or resize the panel from the tab's body; the open/close animation must run
  inside a fixed frame (see the invariant in `architecture.md`).

The tab's own directory belongs under
`DynamicIsland/components/<Feature>/`, split into `Models/`, `Services/`,
`ViewModels/` and `Views/` only as far as the feature needs them. Shelf is the
full example; Timer and Color Picker are smaller ones.

## 7. Put it in the tab row

`DynamicIsland/components/Tabs/TabSelectionView.swift`

- Add a `labels` entry: short title and SF Symbol.
- Add a `badge(for:)` colour only when the tab has an attention state.
- No width arithmetic here. The row is measured by the housing-clearance test.

## 8. Drop routing, only if it accepts files

`DynamicIsland/models/DynamicIslandViewModel.swift`

- A tab with its own drop target: add it to `tabsWithOwnDrops`.
- A tab that opens when a drag rests on its icon: add it to
  `springLoadedTabs`.
- Otherwise entry drops route through `routesDropsToShelf` /
  `notchDropTarget()`. Keep the rule that a hidden tray never imports.
- Add a focused test for the combination matrix. `FileConvertTests` has the
  template (`testOptionalToolCombinationsNeverStoreDropsInAHiddenFileTray`).

## 9. Settings and Feature Management

- `DynamicIsland/components/Settings/SettingsView.swift`
  - `SettingsTab` case, section group, title, icon, tint, sidebar list, and
    the detail `switch`.
  - `SettingsSearchIndex` entries for every searchable control, including the
    new tab's enable switch. Use `SettingsTab.x.highlightID(for:)` so search
    focuses the right row.
- A settings page under `DynamicIsland/components/Settings/`, wired into the
  detail switch.
- `DynamicIsland/components/Settings/FeatureManagementSettings.swift`: add a
  row with its permission and background note, pointing at the settings tab.
- If the tab replaces an old destination, alias the old name in
  `SettingsWindowController.showWindow(tab:)` so existing links keep working.

## 10. Strings

User-visible text uses `String(localized:)` or `Text("…")`; the build extracts
them because `SWIFT_EMIT_LOC_STRINGS = YES`. Add translations to
`DynamicIsland/Localizable.xcstrings` if you maintain that file. Do not hardcode
Chinese or English in a new view.

## 11. Tests and verification

- `DynamicIslandTests/NotchHousingClearanceTests.swift`
  - Update the expected standard tab count.
  - Confirm the test still renders the real row and fails if the last tab would
    sit under the camera housing.
- Add an availability/routing test: a disabled tab resolves to the first
  enabled tab; a stale saved-order entry is ignored; a disabled tab is absent
  from `NotchTabAvailability.current.tabs`.
- Add drop tests if step 8 applies.

```sh
xcodebuild -project DynamicIsland.xcodeproj -scheme DynamicIsland \
  -configuration Debug -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build

xcodebuild -project DynamicIsland.xcodeproj -scheme DynamicIsland \
  -configuration Debug -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO test \
  -only-testing:DynamicIslandTests/NotchHousingClearanceTests \
  -only-testing:DynamicIslandTests/ClosedHUDSizingTests \
  -only-testing:DynamicIslandTests/FlyoutFrameCalculatorTests
```

Run the full `-only-testing:DynamicIslandTests` suite before committing.

## Pitfalls

- A `NotchViews` case with no `ContentView` branch resolves to a blank surface;
  `resolve` cannot invent a view.
- A case with no `Defaults` gate is always on. Add the switch in the same
  change, or the tab cannot be turned off.
- `@Published` in the coordinator emits before assignment. If a handler reads
  `currentView` inside `sink`, hop one run-loop turn.
- Adding a tab raises the minimum open notch width on every screen. Do not
  compensate by shrinking `TabButton` constants for one feature.
- Do not start timers, watchers or permission prompts from a tab's `init` or
  `body`. Feature work belongs in a manager with a demand gate.
