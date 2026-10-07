# Next-version review evidence

See [review and priorities](../../next-version-review-2026-10-06.md).

- Two diagnostic sequences reproduced against current production Agent sources: [observations](replay.json), [probe](AgentReviewProbe.swift).
- The probe asserts the defects it is measuring. Exit 0 means reproduction succeeded, not that the app passes acceptance.
- 313 product/native-test Swift files were unchanged during this review; all 322 source entries from the preceding verification receipt still match. [Receipt](verification.json).
- No product/test edits, installation, settings changes, real Agent access, commit or push.
- No native UI replay of tab disable/fallback, actual-client long-ID occurrence check, performance benchmark or soak. The preceding full suite was not rerun.

## Reproduction

From the repository root, create isolated support by removing only the original harness's `@main` marker:

```sh
mkdir -p /tmp/atoll-next-version-review
python3 - <<'PY'
from pathlib import Path
source = Path('tests/AgentConversationRegression.swift').read_text()
Path('/tmp/atoll-next-version-review/RegressionSupport.swift').write_text(
    source.replace('@main\nstruct AgentConversationRegression', 'struct AgentConversationRegression')
)
PY
xcrun swiftc -swift-version 5 \
  -module-cache-path /tmp/atoll-next-version-review/module-cache \
  DynamicIsland/managers/Agents/*.swift \
  DynamicIsland/managers/Agents/Sources/*.swift \
  DynamicIsland/managers/Agents/Terminals/*.swift \
  DynamicIsland/utils/AtollTemporaryFiles.swift \
  DynamicIsland/utils/PipeReadWaiter.swift \
  DynamicIsland/utils/PrivateContentFile.swift \
  DynamicIsland/helpers/AppRuntimeEnvironment.swift \
  /tmp/atoll-next-version-review/RegressionSupport.swift \
  docs/audit/2026-10-06-next-version-review/AgentReviewProbe.swift \
  -o /tmp/atoll-next-version-review/agent-review
/tmp/atoll-next-version-review/agent-review
```

The fake service uses a temporary preference suite and nonpersistent session store. The fake Codex client and terminals never run installed clients, terminal commands or approvals. `allow: false` records one fake decline reply. App settings and actual clipboard content are not accessed. The run was permitted outside the shell sandbox solely for the fixture's temporary CFPreferences writes.

Compile completed with SDK macro and existing Swift implicit-capture warnings: [log](compile.log.md).
