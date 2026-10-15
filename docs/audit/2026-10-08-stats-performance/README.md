# Stats performance evidence — 2026-10-08

Baseline source: `b6a518d9ccf8ffc6f33fe6e6e1de0fab47c644e8`. Final source
identities, build receipts and artifact hashes are recorded in `receipt.json`.
The user authorized local improvements; the installed application was not replaced.

## Artifacts

- `baseline-collector.txt`: original collector probe, 25 samples with valid GPU,
  CPU temperature and frequency readings. The first sample is excluded from
  warm summaries. The original synchronous method bodies and published state
  were extracted from the baseline manager; process/volume work was excluded.
- `revised-collector.txt` and `measurements.json`: final manager/sampler benchmark,
  25 samples per phase, using a private Defaults suite. A counting subscriber
  observes notifications; it does not render SwiftUI.
- `native-tests.log`: final isolated host run, 26 passing tests, including all
  nine Stats regressions and the related runtime/reliability tests.
- `baseline-accessibility.log`: the existing settings accessibility test also
  fails on the older host with an empty labels array. This test was excluded
  from the final focused run; it is not recorded as passing.
- `build-receipts.txt`: final Debug test build and Release build success lines,
  commands, warning excerpts and original log locations.

The full `.xcresult` bundles remain under `/tmp/atoll-stats-probe/native/`.
No production application launch, process-list probe, installation, commit or
push was performed for this improvement.

## Replay the revised benchmark

Run from the repository root after a Debug `build-for-testing`:

```sh
python3 docs/audit/2026-10-08-stats-performance/prepare-benchmark.py
xcrun swiftc -swift-version 5 -O -parse-as-library \
  -module-cache-path /tmp/atoll-stats-probe/module-cache -I Build/Debug \
  Build/Debug/Defaults.o \
  -Xlinker /Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/lib/clang/21/lib/darwin/libclang_rt.profile_osx.a \
  /tmp/atoll-stats-probe/after/MeasuredStatsManager.swift \
  /tmp/atoll-stats-probe/after/Support.swift /tmp/atoll-stats-probe/after/Main.swift \
  DynamicIsland/models/StatsSampling.swift DynamicIsland/models/StatsModels.swift \
  DynamicIsland/models/CPUMetrics.swift DynamicIsland/helpers/AtollRuntimePolicy.swift \
  DynamicIsland/components/Stats/StatsFormatting.swift DynamicIsland/components/Stats/ProcessStats.swift \
  DynamicIsland/utils/SystemStatsSampler.swift DynamicIsland/utils/CPUSensorCollector.swift \
  DynamicIsland/utils/GPUInfoCollector.swift DynamicIsland/utils/AppleHardwareInfo.swift \
  DynamicIsland/utils/IOKitHelpers.swift DynamicIsland/utils/IOReportBridging.swift \
  DynamicIsland/utils/SMC.swift DynamicIsland/managers/Agents/ProcessRunner.swift \
  DynamicIsland/utils/PipeReadWaiter.swift -o /tmp/atoll-stats-probe/after/probe
LLVM_PROFILE_FILE=/tmp/atoll-stats-probe/after/defaults.profraw \
  /tmp/atoll-stats-probe/after/probe
```

The profile runtime path is specific to this Xcode installation and is needed
because `Defaults.o` was produced by the test build. Adjust it for another
toolchain. SMC/IOReport must actually succeed; restricted runs without valid
temperature/frequency readings are not comparable to the full baseline.

Instrumentation surrounds only the snapshot assignment. The sampler wrapper
measures the actor call, including its scheduling, and adds CPU detail demand
in the second phase without enabling process scans. Enqueue timing surrounds
`refresh()` on MainActor. Each phase drops its first sample from summaries.
The two-millisecond heartbeat also includes OS scheduling delays and is not
a frame-rendering measurement.
