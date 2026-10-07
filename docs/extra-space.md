# Extra Space

Enable **Settings → Utilities → Extra Space → Enable Extra Space**. The feature
is off by default. Once enabled, **Extra Space** appears in the main tab row
beside Home, Stats and Agents, and can be reordered like the other tabs.

Set **Open Extra Space** in this page or Settings → Shortcuts for direct access.
The shortcut is unassigned by default and follows the Shortcuts master switch.
It opens reading mode when the feature is enabled; otherwise it opens Extra
Space settings without enabling it. See [feature management and runtime
policy](lightweight-setup-and-agent-status.md) for lightweight setup choices.

The tab opens in reading mode. Double-click the text area or click **Edit** to
type, select and change text. **Paste** enters editing and inserts at the cursor.
**Copy all** copies the document. **Cmd+S** or **Save** writes locally and finishes
editing; autosave protects
changes during editing. The saved status is informational and does not re-enter
editing. A single click selects reading text without entering editing; a double
click enters editing. Double-clicking while already editing retains native word
selection. Cmd+S also finishes active composition through the same Save path.
Composition and editability finish after SwiftUI's view-update pass, because
changing native editability can commit text and notify the document model.
Double-click entry uses AppKit's [click count](https://developer.apple.com/documentation/appkit/nsevent/clickcount)
in the native text view's mouse handler.

While editing, vertical scrolling stays inside the text. After Save, the notch's
close swipe (up by default) saves and closes from anywhere in the reading area,
without moving the text. Another Edit click restores editing and scrolling.
Scrolling in the opposite direction and the scrollbar remain available for
reading. Gesture direction, sensitivity and enablement follow existing notch
settings. Escape also closes after active input-method composition is dismissed.

The default outer height matches ordinary main tabs (200 points). Long content
scrolls inside the editor and never expands the notch. There is no separate
automatic size increase for this feature.

Use **Cmd+A/C/X/V** to select all, copy, cut and paste; **Cmd+Z** undoes the last
edit and **Cmd+Shift+Z** redoes it. **Ctrl+V/Z/Shift+Z** are also accepted while
the editor has focus; other Control bindings retain native behavior. Keyboard,
context-menu and toolbar pastes use the same plain-text editing path. Each
paste has its own undo boundary, including replacing selected text.

Changes save after 500 ms without another edit. Leaving the tab saves
immediately in the background; normal app termination flushes pending changes.
The text is stored as UTF-8 in
`~/Library/Application Support/Atoll/ExtraSpace/content.txt`. A force quit can
lose changes since the last save. Save failures leave the draft in memory and
show a retry action; a load failure never replaces the saved file with an empty
document.

Disabling the feature hides its tab and retains the text. Selection and reading
position survive tab/notch remounts within the current run, per display. Text
survives restarts; reading position and undo history do not.

The editor uses `NSTextView` inside `NSScrollView`; text changes are observed
only in this tab, and serialized atomic saves run off the main thread. Both the
SwiftUI notch and AppKit window use the existing standard sizing path,
regardless of document length. No new package is required.

The keyboard regression was caused by depending on app/menu shortcut routing:
the native undo stack had entries, but `Cmd+Z` was unhandled by the borderless
notch window. The focused text view now handles editing key equivalents and
Control aliases directly. Toolbar paste runs after SwiftUI's view update to
avoid publishing model changes during that update. These changes follow
AppKit's [key-equivalent handling](https://developer.apple.com/documentation/appkit/nsresponder/performkeyequivalent(with:))
and [delegate-provided undo managers](https://developer.apple.com/documentation/appkit/nstextviewdelegate/undomanager(for:)).
The isolated manager disables automatic event grouping; the delegate brackets
each native mutation explicitly, so a paste remains independently undoable and
subsequent typing, cut and delete actions keep a valid undo group.
See [UndoManager grouping](https://developer.apple.com/documentation/foundation/undomanager/groupsbyevent).

Verification: `DynamicIslandTests/ExtraSpaceTests` covers autosave ordering,
termination flushing, Unicode/newline recovery, load/save failures, native
composition and undo/redo, keyboard and toolbar paste, selected-text replacement
and deletion, clipboard copy/cut, Edit/Save focus transitions, saved-mode close
swipes, double-click entry and Cmd+S saving in the real tab (including empty text
and active composition), default height parity, two editors sharing text, a long editor's
selection/scroll restoration, and rendered tab/settings previews. Clipboard
tests use private pasteboards and never replace the user's clipboard. Manual
acceptance should also exercise real input-method candidate windows, Cmd+V,
scroll momentum, multiple displays and feature toggling on the main tab row.

Validated on 2026-10-06: all 13 Extra Space tests passed, including double-click
entry, Cmd+S saving with active composition, releasing keyboard focus, closing
without scrolling in reading mode, and restoring native scrolling after Edit.
Gesture events are synthesized in
the tests; physical trackpad feel remains a manual acceptance check.

Audit safeguards (2026-10-06): content is limited to 5 MiB without silent
truncation; oversized or invalid files remain untouched. Repeated Save and
teardown reuse a written revision. Settings shows storage use and offers local
file reveal and explicit previous-version recovery. At most 200 undo groups
are retained, reduced for large documents. See [limits and recovery details](project-audit-fixes-2026-10-06.md).

## Finding and exporting

**Find** or **Cmd+F** opens AppKit's find bar, including in reading mode. **Cmd+G / Cmd+Shift+G** navigate matches when
the text view is the responder; the native bar supplies its own navigation controls. Escape hides the find interface before closing
the notch. Search does not enter editing or change the document/undo history. The bar consumes existing internal height.
[Native find support](https://developer.apple.com/documentation/appkit/nstextview/usesfindbar) provides incremental search.

**Export** opens an [NSSavePanel](https://developer.apple.com/documentation/appkit/nssavepanel) for a `.txt` copy of the current
committed document. An immutable UTF-8 snapshot writes atomically off the UI thread; export does not modify local persistence,
edit state or undo. Cancelling has no write; errors appear on the tab. The notch suppresses automatic close while the find bar or
export panel is open, and releases that suppression when they finish or the view disappears.

The settings close hint follows the enabled/reversed gesture preference. No default height increase, note list or clipboard history was added.
