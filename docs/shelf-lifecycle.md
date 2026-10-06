# Shelf resource lifecycle

Updated 2026-09-28. The shelf stages references and small previews for an app that remains running all day. It does not pre-load file contents or run a background cleanup loop.

## Resource limits

| Resource | Policy |
| --- | --- |
| Thumbnail cache | LRU, at most 48 entries and 8 MiB of accounted image storage. This is a cache limit, not a total process memory limit. |
| Quick Look thumbnail work | At most two requests at once; shared requests have individual cancellable consumers. A request that does not answer is cancelled after 30 seconds. |
| Card images | Only cards intersecting the scroll viewport request thumbnails. Hidden cards release their image references. The eager row remains for marquee hit testing. |
| Drag preview | Rendered once when a drag starts; a group uses its primary item and a count badge. No per-card preview bitmap is retained while idle. |
| Incoming attachments | Ordinary files remain references. File representations are copied inside the provider callback into an owned directory; the provider's source is never deleted by Atoll. Shelf batches are serialized. |
| Provider cancellation | Cancels supported Progress objects and resumes waiters exactly once. An unanswered request expires after 30 seconds. A late callback cannot resume a cancelled waiter. |
| File cleanup | A serial utility queue and one wake at the next expiry. No recurring sweep. |
| Clipboard | Releases through pasteboard ownership callbacks, without polling. |
| Hover fallback | Runs only for hidden-edge activation or an active hover interaction. |
| App memory monitor | Evaluates on startup and on system memory-pressure events; no eight-second poll. Memory pressure also clears Shelf's cache and pending thumbnails. |

The high-memory restart prompt is checked at startup and during system memory pressure; it no longer acts as a periodic per-process limit detector.

The visible card images, framework caches, enabled media features, and user's staged text still contribute to process memory. A populated Shelf is not expected to return to its cold-launch resident size after every close.

## File ownership and handoff

`ShelfFileLifetime` coordinates saved references, active leases and per-file expiration dates. Dragging, sharing, copying, previewing and thumbnail generation use leases. Clearing or disabling Shelf removes references; it does not bypass an active lease. Only data under Atoll's own temporary `Shelf` directory can be reclaimed. Original files and the item provider's temporary source remain untouched.

- A cancelled operation releases its lease. A successful external handoff preserves a ten-minute grace period for its files.
- An individual handoff's expiry is stored in `.handoffs.json`. A later handoff of another file does not extend the first file's lifetime. Restart reads the existing dates before cleanup.
- While a lease is active, a crash-recovery grace is recorded on disk. Normal completion updates/removes that protection. A forced process exit cannot observe subsequent changes to the clipboard or a receiving app.
- Newly created import directories have a one-minute creation grace so a concurrent sweep does not race with their creation; file-copy and ZIP work also hold explicit leases. Copied representations receive a handoff grace while the import becomes a saved item.
- Sharing completes through success, failure or user-cancellation callbacks. There is no fixed two-second successful-completion fallback.
- Only successful security-scope starts are stopped. An ordinary non-sandbox file URL remains valid when `startAccessingSecurityScopedResource()` returns false.

An external drag's completion does not indicate that the destination has finished a later upload. The finite grace covers handoff latency; it cannot guarantee an arbitrarily delayed external reader. Quitting Atoll also ends its active leases; persisted grace protects the next launch. Operating-system purging of temporary storage remains possible.

## Persistence and recovery

An intentionally empty saved list is removed from disk. Failed decoding is distinguished from an empty list: the exact original JSON is preserved, valid entries can be recovered, and the first subsequent write creates an `items.recovery-<UUID>.json` copy. Save failures are shown in Shelf and suppress destructive cleanup. The presence of recovery data continues to suppress cleanup across restarts because it may refer to temporary files not present in the recovered list.

If a recovery warning appears, inspect/restore the recovery JSON in `~/Library/Application Support/DynamicIsland/Shelf` and the corresponding temporary files before retiring the recovery copy. A malformed `.handoffs.json` also disables cleanup and is retained. This intentionally favors recovering user data over automatically deleting uncertain files.

Missing or disconnected volumes no longer cause items to vanish from Shelf. Reconnect the volume, retry access, or remove the item explicitly. Turning Shelf off confirms the count to clear and explains that original files remain in place. Imports already queued before a clear cannot repopulate the cleared Shelf.

## Verification

Use the existing local package checkouts:

```sh
xcodebuild -project DynamicIsland.xcodeproj -scheme DynamicIsland \
  -configuration Debug -destination 'platform=macOS' -derivedDataPath Build \
  -disableAutomaticPackageResolution CODE_SIGNING_ALLOWED=NO \
  test -only-testing:DynamicIslandTests/ShelfTests
```

The regression fixtures use isolated directories and a named test pasteboard, not the user's general clipboard. The application delegate skips its launch integrations when hosted by XCTest.

The focused suite has 26 passing tests and covers lifetime cleanup, persisted expiry, corruption recovery, prefix/symlink ownership, clipboard replacement, real sharing callback semantics, metadata updates, provider cancellation, preview access and thumbnail limits. Generating 60 real PNG thumbnails retained 48 entries with 2,408,448 accounted bytes, then clearing returned cache entries, accounted bytes, running requests and queued requests to zero. One hundred repeated file leases left zero active leases and no scheduled cleanup wake after the last reference was removed.

These are scoped resource checks, not a long-duration CPU/RSS profile of all enabled Atoll features. Finder drag-out, an actual AirDrop transfer, multiple monitors and sleep/wake still require interactive acceptance on the user's setup. No transfer to another person is performed by the automated checks.

## API references

- [File representations must be copied before their callback returns](https://developer.apple.com/documentation/foundation/nsitemprovider/loadfilerepresentation(fortypeidentifier:completionhandler:))
- [Sharing failure and user cancellation](https://developer.apple.com/documentation/appkit/nssharingservicedelegate/sharingservice(_:didfailtoshareitems:error:))
- [Cancelling thumbnail requests](https://developer.apple.com/documentation/quicklookthumbnailing/qlthumbnailgenerator/cancel(_:))
- [Pasteboard ownership](https://developer.apple.com/documentation/appkit/nspasteboard/declaretypes(_:owner:))

Audit safeguards (2026-10-06): loads/saves use a serial utility queue and
coalesced snapshots. New imports enforce item, text, queue and owned-file
budgets; zip uses bounded snapshots and capacity reservations. File-version
cache keys and per-URL invalidation avoid stale images. Settings exposes storage
limits and the saved-data folder. See [exact limits and acceptance boundaries](project-audit-fixes-2026-10-06.md).
