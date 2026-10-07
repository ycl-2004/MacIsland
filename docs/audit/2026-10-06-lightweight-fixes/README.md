# Local verification — 2026-10-06

Implementation: [lightweight setup and Agent status](../../lightweight-setup-and-agent-status.md).
Baseline: `ce417b73631d1b59126496ca4d180ca756652c6d`.

| Check | Result | Evidence |
| --- | --- | --- |
| Native regression | 36 tests, 0 failures | [native log](native-tests.log.md) |
| Agent state acceptance | 51/51 | [observations](state-observations.json) |
| Exact plugin transport preamble | 7/7, fake children only | [observations](plugin-observations.json) |
| Full Agent regression | 15/15 groups | [log](agent-regression.log.md) |
| Release and deep/strict signature | Passed | [build/signature](release-build.log.md) |
| Diff whitespace | Passed | [receipt and source hashes](verification.json) |

Two implementation bugs have recorded failing-then-passing evidence:
[Stats publication timing](stats-visibility-before.log.md) and
[plugin settlement gap](plugin-settlement-before.log.md).
Native snapshots assert/render the settings destination and Extra Space,
using isolated test storage and private pasteboards.

No application installation, commit/push, real Agent CLI/session/config,
production approval or user clipboard operation was performed.

Still unverified: installed Agent versions, installed-app global shortcut/
mouse/trackpad behavior, fixed-workload performance comparisons and a 24–72-hour
sleep/multiple-display/reconnection soak. Legacy identity-less events and
unreachable/forced-exit plugin transport retain documented limitations.
