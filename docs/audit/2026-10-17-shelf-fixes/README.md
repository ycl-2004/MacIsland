# Shelf fix evidence — 2026-10-17

Scope: confirmed Shelf errors and measured responsiveness costs, without new product features.
See [the fix report](../../shelf-fixes-2026-10-17.md) and [baseline](../2026-10-17-shelf-assessment/README.md).

## Results

| Check | Evidence | Result |
| --- | --- | --- |
| Existing Shelf regression suite | `existing.log`, `existing.summary.json` | 26 passed |
| New Shelf regressions | `regressions.log`, `regressions.summary.json` | 14 passed |
| Existing disable/persistence/clear regression | `disable.log`, `disable.summary.json` | 1 passed |
| Same baseline diagnostic probes | `performance.log`, `measurements.json` | 5 passed |
| Interactive native drag into local receiver | `native-drag.log`, `native-drag.summary.json` | 1 passed |
| Debug build-for-testing | `debug-build.log` | Succeeded |
| Release build | `release-build.log` | Succeeded |

`shelf-layout.png` is a rendered snapshot of the real Shelf view with 50 text items.
The application keeps only a small live card subtree; the image is not a mock-up.

## Reproduction

The automatic regressions remain in `DynamicIslandTests/ShelfReliabilityTests.swift`.
Use the isolated host runner, with a fresh `/tmp` output directory per invocation:

```sh
python3 Tools/verify-stability.py --native-only --only-tests ShelfReliabilityTests \
  --output /tmp/atoll-shelf-regression-recheck
python3 Tools/verify-stability.py --skip-build --native-only --only-tests ShelfTests \
  --output /tmp/atoll-shelf-existing-recheck
```

To rerun measurements, temporarily copy `ShelfFixProbeTests.swift` from this directory
into `DynamicIslandTests`, build and select `ShelfFixProbeTests`, then remove that temporary
copy. The modified batch probe calls the production bulk-removal path; other timing probes
retain the baseline workload. Rename verification now prepares the native drag writers.

`ShelfNativeDragProbeTests.swift` is an **interactive** fixture, intentionally excluded from
the normal suite. It displays a real Shelf above a local AppKit drop target, renames the test
file after display, then waits for a drag. The recorded native drop contained `Renamed-test.txt`;
the file and Shelf reference remained, and drag state ended. It does not test Finder or upload
anything. The CUA connection was delayed and subsequently launched the copied host outside
XCTest; that extra process, its children and its unique preference domain were stopped/removed.

An initial geometry regression caught an 8 px shift at the end of a 200-item lazy row.
The implementation now includes spacing in each cell's fixed extent; final left-to-right
and right-to-left native-frame comparisons pass. Failed intermediate results are not counted
as successful acceptance checks.

## Interpretation

Times are local Debug samples, not benchmarks under controlled system load. Initial layout
means synchronous view/window construction and layout; deferred rendering is not included.
The heartbeat is a main-actor scheduling sample, not per-frame latency. The 50-file parser
probe still uses the sequential compatibility API and showed no throughput improvement.
Provider isolation is tested independently with a deliberately delayed provider.

The user subsequently authorized replacing `/Applications/Atoll.app`. Installation and launch are verified in `installation.json`; the previous app is retained under `Build/InstalledBackups/ShelfFix-20261017-194122-0d1942bc/OriginalAtoll.app`. Deep/strict signature verification and both binary hashes passed; the running installed process is PID 5158. No commit, push or publication was performed.
Finder/browser destinations, remote-volume latency, multi-monitor behavior and sleep/wake
remain outside this verification. Full `.xcresult` bundles remain at the `/tmp` paths in the
step receipts; logs and summaries are retained here for durable review.
