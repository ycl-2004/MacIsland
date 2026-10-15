# Backpressure fix evidence — 2026-10-10

- [Native summary](native-summary.json): final 340 tests, no failure or skip.
- [Verification steps](verification-steps.json): final build and all synthetic checks succeeded.
- [Agent results](agent-results.txt): includes stalled-reader timeout/cancellation, FIFO and stubborn owned-child cleanup.
- [Slow-save results](slow-save-results.txt): two writes per store and latest file contents confirmed.
- [RPC result](rpc-results.txt): final within-budget prompt, 160ms timeout / 14.2ms MainActor heartbeat gap.

Reproduce with a fresh output directory:

```sh
python3 Tools/verify-stability.py --output Build/VerificationRuns/backpressure-verify-new
python3 docs/audit/2026-10-10-background-review/slow-save-probe.py Build/VerificationRuns/backpressure-save-new --expect-fixed
python3 docs/audit/2026-10-10-background-review/rpc-backpressure-probe.py Build/VerificationRuns/backpressure-rpc-new --near-byte-limit
```

Raw build/test logs remain in Build/VerificationRuns. These tests use synthetic peers/files. Real Agent CLI sessions, sanitizer and 24–72-hour soak were not run. The original review evidence remains archived separately.

Installation evidence: [receipt](installation.json), [BuildInfo](build-info.json), [installer source](install.py), [lifecycle source](AppLifecycle.swift). Installer/lifecycle sources are archived for review; their paths identify the local build receipt and are not portable install commands.

The first normal-exit helper reported failure. The native Atoll Quit menu was used, then a fresh NSWorkspace query confirmed no old instance before replacement. The installed bundle signature/team, binary SHA-256 and current-source identity were verified; the old bundle was retained and its binary identity verified. CUA launched the replacement; NSWorkspace confirmed its full executable path and finishedLaunching. Extra Space hash after normal save matched after replacement/launch. No forced termination was used.

[Installed smoke summary](installed-smoke-summary.json), [13 startup samples](installed-resources.jsonl), [later physical snapshot](installed-physical-snapshot.jsonl). FD count stayed 29 and direct children stayed 3. Startup RSS varied and must not be treated as a long-run idle benchmark.
