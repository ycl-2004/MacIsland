# Stats responsiveness improvement

Date: 2026-10-08. Expensive periodic hardware reads now run in a serialized
background actor. MainActor requests a sample and publishes its completed
snapshot. This removes the measured synchronous polling cost from the UI path;
the user's intermittent hitch has not yet been captured in the installed UI.

## Changes

- `SystemStatsSampler` owns the stateful hardware collectors, Mach buffers and
  counter baselines. Requests coalesce while a sample is pending. Cancelled or
  old monitoring generations cannot publish after stop/restart; clearing history
  also invalidates an older pending result.
- One `StatsSnapshot` publishes metrics and their 30-point histories together.
  The unused Stats observation was removed from the notch root. Process results,
  disk capacities and monitoring state remain separate updates.
- Enabled graphs request basic readings. Each visible detail panel contributes
  its own demand, so closing one window does not disable another. CPU sensors,
  per-core data, process scans, network interface details and volume capacities
  are collected only when their details need them.
- Temperature lookup short-circuits and caches a working primary key. Process
  rows keep their PID identity across refreshes. The timer requests background
  work during Cocoa control tracking, using the main run loop's common modes.

Network/disk totals count sampled periods. Enabling a hidden metric establishes
a new baseline instead of averaging across its disabled time. CPU frequency
requires two readings after a detail panel opens. Hidden histories retain their
last collected values. Existing polling preferences, runtime lock/power policy
and UI layout are preserved; no dependency was added.

## Measurements

Apple M4, 10 CPU cores, macOS 27.0.1. Optimized Swift 5 probe, 25 samples at
roughly one-second intervals per phase; each summary excludes its first sample.
GPU, temperature and frequency reads succeeded in the full phases. Evidence and
the revised benchmark harness are in the [audit directory](audit/2026-10-08-stats-performance/README.md).

| Observed path | Executor | Warm mean (ms) | Maximum (ms) |
| --- | --- | ---: | ---: |
| Original full synchronous collector | MainActor | 22.415 | 36.441 |
| Overview: sample request | MainActor | 0.110 | 0.178 |
| Overview: snapshot publication | MainActor | 0.009 | 0.019 |
| Overview: collection | background actor | 4.294 | 8.154 |
| All graphs + CPU details: sample request | MainActor | 0.122 | 0.184 |
| All graphs + CPU details: snapshot publication | MainActor | 0.011 | 0.016 |
| All graphs + CPU details: collection | background actor | 18.352 | 23.926 |

The original warm samples emitted 28.375 notifications on average; the revised
probe emitted exactly one per sample in both phases. The maximum interval of a
heartbeat requesting a two-millisecond wake-up was 31.605 ms. That includes OS
and executor scheduling delays, and does not establish an absence of UI hitches.

The original probe collected every metric/detail regardless of graph settings.
The revised overview requests the default CPU/memory/GPU graphs; its second
phase enables all graphs and CPU details. These are separate observations of
the UI and collection paths, not a controlled whole-app speedup percentage.
The revised collector still takes milliseconds; that work runs away from
MainActor. The benchmark excludes SwiftUI rendering, process scanning and
volume-capacity reads. Snapshot timing includes a counting Combine subscriber,
not actual view recomputation. Notification counts are not render counts.

## Verification and limits

Final Debug `build-for-testing` and Release `build` passed with signing disabled.
The new Stats manager/sampler introduced no remaining compiler warning; existing
project warnings remain. The isolated native host passed 26 focused tests:
nine Stats tests, seven runtime-policy tests and ten reliability tests.

Stats coverage includes slow samples without blocking MainActor, bounded and
coalesced requests, one coherent publication, stop/restart rejection, history
clearing, independent detail demand, worker starts during control tracking,
stable process identity and overview exclusion of unused hardware/details.

One existing settings accessibility test returned an empty labels array in both
the revised host and the older known test host. It was excluded from the final
26-test run; the [baseline failure](audit/2026-10-08-stats-performance/baseline-accessibility.log)
is retained. The full suite and installed UI were not claimed as passing.

The local Release bundle is `Build/Release/Atoll.app`. `/Applications/Atoll.app`
was not replaced or relaunched. No commit or push was performed. Actual popover
interaction, frame hitches during normal use, energy/RSS and long sleep/display
soak behavior remain field checks. The immediate next acceptance step is to
run the new build with the user's normal Stats settings and capture an
Instruments trace if a hitch remains.

API basis: [Swift actor isolation and detached tasks](https://docs.swift.org/swift-book/documentation/the-swift-programming-language/concurrency/),
[Cocoa run-loop modes](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/Multithreading/RunLoopManagement/RunLoopManagement.html),
and [MainActor.assumeIsolated](https://developer.apple.com/documentation/swift/mainactor/assumeisolated(_:file:line:)).
