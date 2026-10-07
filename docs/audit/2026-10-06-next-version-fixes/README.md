# Next-version local verification — 2026-10-06

Implementation: [N01–N08 changes](../../next-version-fixes-2026-10-06.md).
Baseline commit: `ce417b73631d1b59126496ca4d180ca756652c6d`.
This batch includes and preserves the preceding uncommitted implementation.

| Check | Result | Evidence |
| --- | --- | --- |
| Native regression | 68 tests, 0 failures | [native log](native-tests.log.md) |
| Agent request identity and conversation regression | 16/16 groups | [Agent log](agent-regression.log.md) |
| Agent state acceptance | 51/51, 0 gaps | [observations](state-observations.json), [log](state-acceptance.log.md) |
| Signed Release and deep/strict signature | Passed | [build and signature](release-build.log.md) |
| Source identity, links and whitespace | Passed | [receipt](verification.json) |

The native run covers `NextVersionReliabilityTests` (10), `ExtraSpaceTests` (13),
`ShelfTests` (26), `LightweightPolicyTests` (8) and `ContentReliabilityTests` (11).
New fixtures verify actual read-only Find-bar visibility, unchanged text/undo,
Unicode export and failure, Core Animation pulse removal, Shelf hide/recovery,
disabled-tab routing, Calendar query demand, midnight rollover and immediate
reminder completion. The existing 26 Shelf tests retain lease, corruption,
filename, bounded thumbnail and cancellation coverage.

A test of the coordinator exposed recursive `@Published` setter writes in this
implementation. The [failing run](navigation-before.log.md) is retained;
the same coordinator test now passes in the complete native run. The setter
only writes a resolved target when it differs. The original two Agent defects
remain recorded in the [review receipt](../2026-10-06-next-version-review/verification.json);
they are successful assertions in the new Agent regression group.

## Reproduction and test isolation

Build native tests with the `DynamicIsland` scheme, Debug configuration and
macOS destination. This verification used the existing manual development
signing identity. Then run only the five suites listed above.

The initial Desktop-hosted runs stalled before app code in dyld `__open`;
the [sample excerpt](test-host-stall.log.md) records that distinct infrastructure
problem. The successful run copied the built Debug app, package frameworks and
generated `.xctestrun` into `/tmp/atoll-next-version-fixes/native-verified/`.
The copied host has a unique bundle identifier (and therefore its own preference
domain), is re-signed with the existing identity, and includes only the unit test
target. The [test-run manifest](isolated-test-run.xctestrun) records the exact
test selection and host paths. Neither the installed app nor its settings are
used by this final native run.

```sh
xcodebuild test-without-building \
  -xctestrun /tmp/atoll-next-version-fixes/native-verified/DynamicIsland.xctestrun \
  -destination 'platform=macOS'
```

For Agent fixtures, compile all Swift files immediately inside
`DynamicIsland/managers/Agents/`, `Sources/` and `Terminals/`, plus
`AtollTemporaryFiles.swift`, `PipeReadWaiter.swift`, `PrivateContentFile.swift`,
`AppRuntimeEnvironment.swift` and `tests/AgentConversationRegression.swift`
with `xcrun swiftc -swift-version 5`. Run that standalone fixture for 16 groups.
For state acceptance, replace the fixture's `@main` annotation in a temporary
support copy and compile it with `tests/AgentStateAudit.swift`, as described in
the [existing reproduction instructions](../../next-step-review-2026-10-06.md#重跑状态诊断).
Pass the JSON output path as an argument and redirect stdout to a separate log.
The current state harness fails its exit status on any gap.

## Limits and actions

No installation, commit, push, real Agent CLI/config/session or production
approval action was performed. Clipboard test data uses private fixture
pasteboards. Export tests write to temporary folders. The final native host
uses an isolated preference domain; the signed Release remains in `Build/Release/Atoll.app`.

Still unverified: actual Agent versions and user-initiated hooks, installed-app
global shortcuts/focus/trackpad gestures, Find match navigation and field focus,
Save-panel cancel/error presentation, simultaneous real service use, a fixed
workload performance comparison and a 24–72-hour sleep/display/reconnection soak.
No measured CPU, memory or energy improvement is claimed. Existing build warnings
are retained separately from failures in the evidence.
