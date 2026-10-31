# CI native render failure — 2026-10-31

## Goal
Make the native regression step pass on the CI runner again, without changing
product code. This is a test-harness defect: the onboarding preview test
asserted a pixel count that only held on a 2x display.

## Evidence that CI was red
`gh run list` shows four consecutive failures on `main` since 2026-10-19. The
latest (`41225535804`, commit `1efd13c`) failed in **Native and fixture
regressions** with exit 65; **Release build** was skipped. The uploaded
`stability-macos-26` artifact reports:

```text
testIdentifierString : OnboardingPermissionTests/testRenderSetupPagesInEnglishAndChinese()
failureText          : XCTAssertGreaterThan failed: ("470") is not greater than ("500")
result               : Failed
passed 384 / failed 1 / skipped 2 / total 387
```

The 2026-10-19 runs (`39294637349`, `39303339701`) failed with the same
`Native tests failed (65)`; their artifacts have expired, so they are recorded
here as the same exit code, not as a re-verified identical assertion. Those runs
also printed `Metal Toolchain download failed after 5 attempts` while the step
still passed, because `xcrun -f metal` resolved.

## Root cause
`render(_:size:name:dark:)` assigned the `NSHostingView` directly as the window
`contentView` and asserted `bitmap.pixelsWide > 500`.

`OnboardingDataUseView` (`.frame(width: 470)`) is rendered into a 526x420
window. During the `await Task.sleep` in the helper the run loop lets AppKit
resize the window to the hosting view's SwiftUI ideal size (470x310 pt), while
the fixed-size onboarding pages (540x640) keep the window size because their
ideal size matches.

Locally the assertion passed only because the display is 2x: 470 pt renders as
940 px, which is still `> 500`. The CI runner is 1x, so the same layout produced
470 px. Instrumented run:

```text
DBG before sleep data-use-zh-Hans hosting (0,0,526,420) win (0,0,526,420)
DBG after  sleep data-use-zh-Hans hosting (0,0,470,310) win (0,0,110,470,310)
```

The local `xcresult` confirmed the same 470 pt layout: the attached
`data-use-zh-Hans` PNG was 940x620 (470x310 at 2x), not 1052x840.

## Change
`DynamicIslandTests/OnboardingPermissionTests.swift` only:

- A plain `NSView` container owns the requested frame and becomes the
  `contentView`; the hosting view is a child with `sizingOptions = []`.
- The frame is checked after the async yield, before rendering, without resetting
  it immediately before the assertion.
- The assertion checks `hosting.bounds` in points instead of a pixel count, so
  it is independent of display scale and fails if a page is laid out at its
  intrinsic size again.

## Verification
Executed locally on macOS 27.2 / Xcode 27.2 with the CI commands:

| Step | Result |
| --- | --- |
| `python3 -m unittest tests.test_privacy_configuration tests.test_timer_lifecycle` | 10 tests, OK |
| `python3 Tools/verify-stability.py --output /tmp/atoll-ci-verify-3` | PASS, 387/387 passed, 0 failed, 0 skipped |
| `xcodebuild build -configuration Release ... CODE_SIGNING_ALLOWED=NO` | BUILD SUCCEEDED |
| `-only-testing:DynamicIslandTests/OnboardingPermissionTests` | 6 tests, 0 failures |
| `xcresult` attachment sizes | onboarding 1080x1280, data-use 1052x840 (was 940x620) |

The new assertion was checked against the old geometry: 470x310 fails, so it
still catches the regression the old pixel threshold was meant to catch.

## Limits
- GitHub CI has not run on this change; the table is a local execution of the
  same commands. The red runs above are the pre-change state.
- The CI image pins Xcode 26.3 while the local toolchain is 27.2, which is why
  the defect stayed invisible locally. The fix uses only macOS 13+ APIs.
- The Metal toolchain download step remains transient-failure prone. It does not
  fail the job when `metal` is present, so it was left unchanged here.
- SourceKit reports `No such module 'XCTest'` / `'Defaults'` for files in this
  test target. Untouched test files report the same error, so it is a
  workspace-resolution artifact rather than a build error; `xcodebuild` compiles
  and runs the target.
