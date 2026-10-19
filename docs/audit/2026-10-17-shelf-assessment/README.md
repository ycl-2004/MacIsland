# Shelf assessment evidence — 2026-10-17

Assessment: [完整报告](../../shelf-assessment-2026-10-17.md).
Product source baseline: `578a61ec`. Product source, installed application,
production preferences, clipboard and real files were not changed.

## Results

- Debug build-for-testing succeeded. macOS 27.0.1 / Xcode 27.1.
- Existing `ShelfTests`: 26 passed, 0 failed, 0 skipped.
- Diagnostic `ShelfAssessmentProbeTests`: 5 passed, 0 failed, 0 skipped.
- Initial four-probe run also passed; it is not counted as four additional unique tests.
- Both successful summary bundles report no runtime warnings. This does not
  mean the entire build log or system service log was warning-free.

## Files

- `ShelfAssessmentProbeTests.swift`: exact final diagnostic source. It was
  compiled in the synchronized test target, then moved here after execution.
  It deliberately records observations, without making the observed defects
  into required behavior or turning variable timings into CI pass thresholds.
- `probe-baseline.log`, `probe-final.log`: raw diagnostic test output.
- `measurements-baseline.json`, `measurements-final.json`: machine-readable
  `SHELF_ASSESSMENT` records extracted from those logs.
- `probe-baseline-summary.json`, `probe-final-summary.json`,
  `shelf-tests-summary.json`: xcresulttool test summaries.
- `shelf-tests.log`: existing Shelf regression output.
- `probe-final-steps.json`: successful final build/test steps and durations.
- `shelf-layout-fixture.png`: real ShelfView rendered with 50 synthetic short
  text items at 680×170 points, dark appearance; this is not the user's shelf.
- `desktop-host-sample.txt`: sampled failed Desktop-hosted test launch,
  blocked in dyld `__open`, before application code.
- `receipt.json`: environment, artifact identity, run paths and boundaries.

## Interpretation limits

The 600 ms provider delay is injected. The local import fixture consists of
small text files and runs through real NSItemProviders and ShelfDropService.
MainActor heartbeat gaps include scheduling; they are not display frame times.

Drag preview measurements call the actual ImageRenderer path with 40 bytes,
4 KiB, 64 KiB and 1 MiB of repeated ASCII text. The first short sample includes
renderer warm-up. No entire drag session or destination processing is timed.

Shelf layout measurements include creating an NSHostingView and a transparent
NSPanel, attaching the actual ShelfView and forcing synchronous layout. The
selection measurement includes selectAll and immediate layout only; later
SwiftUI transactions and displayed selection appearance are not guaranteed to
have settled at that point. The screenshot is illustrative, not a keyboard or
selection appearance acceptance test. These are Debug diagnostic observations,
not Release UI latency percentiles or proof of frame hitches.

The renamed-source probe renames only its own temporary fixture. It compares
the cached URL used by drag-out with asynchronous bookmark resolution. It
does not transfer files to another application. Existing clipboard tests use
a uniquely named pasteboard, not the general clipboard; AirDrop tests invoke
delegate callbacks and do not send to anyone.

No real Finder/browser drag, AirDrop transfer, NAS, iCloud placeholder,
multi-monitor, sleep/wake, long-duration CPU/RSS or production usage analytics
was performed. Those acceptance scenarios are listed in the assessment.

## Reproduction

The diagnostic source is archived outside the automatic test target. From
the repository root, ensure no file already occupies the temporary target
path, then copy it for the duration of the run:

```sh
test ! -e DynamicIslandTests/ShelfAssessmentProbeTests.swift && \
  cp docs/audit/2026-10-17-shelf-assessment/ShelfAssessmentProbeTests.swift \
     DynamicIslandTests/ShelfAssessmentProbeTests.swift
python3 Tools/verify-stability.py --native-only \
  --only-tests ShelfAssessmentProbeTests \
  --output /tmp/atoll-shelf-assessment-replay
python3 Tools/verify-stability.py --skip-build --native-only \
  --only-tests ShelfTests --output /tmp/atoll-shelf-regression-replay
```

Use fresh output paths on subsequent runs. Remove only the temporary test
copy created for this replay after comparing it with the archive. The layout
probe writes `/tmp/atoll-shelf-assessment-layout.png`; run it serially.
`verify-stability.py` makes an isolated app copy with a unique preference
domain, redirects test content and skips normal app launch integrations.

The first sandbox build could not write Xcode/SwiftPM caches. A reviewed
escalation allowed the build. The first Desktop-hosted execution stalled
before app code; sampling confirmed the same dyld startup issue recorded in
earlier project audits. Only those self-created test processes were stopped.
Running the identical build from `/tmp` succeeded, followed by the final
five-probe build/run. These infrastructure attempts are not product failures.

Full result bundles remain at the paths in `receipt.json`; source build logs
are under `Build/VerificationRuns/shelf-assessment-20261017-native/` and
`/tmp/atoll-shelf-assessment-layout-20261017/`.
