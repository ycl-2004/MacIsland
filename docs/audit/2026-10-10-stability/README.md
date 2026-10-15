# Stability review evidence — 2026-10-10

The [review](../../stability-review-2026-10-10.md) covers the current dirty worktree.
`source-sha256.json` fingerprints inspected/build input source files; `verification.json`
records HEAD, commands, results and limitations. Product files were not edited.

## Results

- Debug test build and Release build succeeded with signing disabled.
- All 311 native unit tests passed, zero failed/skipped. The previously excluded
  settings accessibility test was included and passed. XCUITest was not run.
- Seven Python checks, 16 Agent fixture groups, seven plugin replay cases and
  four guardian fixture cases passed.
- Resource probes use exact source for the JSONL reader and Agent store. The
  Combine and pipe-order probes are controls showing why lifecycle/pipe order
  matters; they are not additional product pass counts.
- The log predicate probe uses synthetic subsystem strings. It reads no actual
  production log content.

`native-summary.json` retains the result/count/time fields from xcresulttool,
omitting device identifiers. The markdown logs are excerpts. Complete build
logs, isolated test host, xctestrun and result bundle remain in
`/tmp/atoll-stability-audit-20261010/`; temporary files are not permanent storage.

`bundle-and-dependencies.json` was captured before this audit's Release rebuild.
It compares the installed bundle with the earlier local Release, both showing
1.0.0 / 1637 despite different binary hashes. `verification.json` separately
records the newly rebuilt Release hash. No application was installed or replaced.

## Reproduction

Use the exact commands recorded under `builds` in `verification.json`. Existing
SwiftPM checkouts and the tracked resolved file were used. Xcode required access
to its ordinary caches outside the workspace; the initial sandbox failure was
an infrastructure limitation, not a compiler failure in product code.

For native tests, copy `Build/Debug/Atoll.app` and `Build/Debug/PackageFrameworks`
into a new temporary directory's `Debug/` folder. Give only the copied app a
unique `CFBundleIdentifier`, sign that copy ad hoc, and copy the generated
`Build/DynamicIsland_DynamicIsland_macosx27.0-arm64.xctestrun` beside `Debug/`.
In each test configuration retain only `DynamicIslandTests`, update
`TestHostBundleIdentifier` and crash-report emphasis to the unique ID, and enable
60 s default / 120 s maximum test timeouts. Do not substitute the installed app.
The test environment redirects content through `AppRuntimeEnvironment`; the
unique ID isolates preferences. The current run's exact temporary manifest path
is recorded in `verification.json`.

```sh
xcodebuild test-without-building \
  -xctestrun /tmp/atoll-stability-audit-20261010/native/DynamicIsland.xctestrun \
  -destination 'platform=macOS' \
  -resultBundlePath /tmp/atoll-stability-audit-20261010/native-results.xcresult \
  -parallel-testing-enabled NO
```

Use a fresh result bundle path on subsequent runs. The above manifest is a
temporary artifact, not a checked-in portable test runner. Adding that runner
and CI integration is R04 in the report.

```sh
python3 -m unittest tests.test_privacy_configuration tests.test_timer_lifecycle
python3 tests/audit_resource_probes.py --output /tmp/atoll-resource-probes.json
python3 tests/OSDGuardianRegression.py
node tests/AgentPluginQueueAudit.mjs

xcrun swiftc -swift-version 5 -module-cache-path /tmp/atoll-audit-modules \
  DynamicIsland/managers/Agents/*.swift \
  DynamicIsland/managers/Agents/Sources/*.swift \
  DynamicIsland/managers/Agents/Terminals/*.swift \
  DynamicIsland/utils/AtollTemporaryFiles.swift \
  DynamicIsland/utils/PipeReadWaiter.swift \
  DynamicIsland/utils/PrivateContentFile.swift \
  DynamicIsland/helpers/AppRuntimeEnvironment.swift \
  tests/AgentConversationRegression.swift -o /tmp/atoll-agent-regress
/tmp/atoll-agent-regress tests/agent-rpc-fixture
```

Agent fixtures use temporary files, fake clients/terminals, an owned loopback
server and a Python JSONL peer. They do not call or access installed Agent CLIs,
credentials or real session files. Guardian tests compile a special helper
that can target only owned `sleep` fixtures.

Long-term soak, actual hardware/permission changes, Instruments, sanitizers,
real Agent integration and distribution signing/notarization remain untested.
See the report for failure-injection cases and acceptance criteria.
