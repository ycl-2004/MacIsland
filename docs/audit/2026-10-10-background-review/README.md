# Background resource review evidence — 2026-10-10

Report: [后台负载与长期运行复核](../../background-resource-review-2026-10-10.md).

- [identity.json](identity.json): parent commit, HEAD, dirty source identity, installed Release identity. Product source was unchanged during this review.
- [native-summary.json](native-summary.json): this run's 334 native tests passed; device identifier removed.
- [verification-steps.json](verification-steps.json): build and all native/Python/Agent/plugin/helper step exit codes.
- [runtime-summary.json](runtime-summary.json), [resources.jsonl](resources.jsonl): 144 main-process readings over a 12-minute run; existing settings and closed notch with Agent activity. Initial phase overlaps tests/build, not a controlled idle-energy benchmark.
- [resource-counters-corrected.jsonl](resource-counters-corrected.jsonl): separate 120-second cumulative CPU/footprint/wakeup readings of the main process and three explicitly identified helpers. This is not a complete process-tree total.
- [settings.json](settings.json): performance-related preference overrides only; `null` means no persisted override, use the source default. No user content or credentials.
- [slow-save-result.log](slow-save-result.log): 13 queued Agent writes; 50.1 MiB extra retained RSS in a blocked-writer text scenario.
- [rpc-probes.json](rpc-probes.json): control timeout works; within-budget 65,525-byte payload stalls MainActor about 3 seconds. The first 400,000-byte case is explicitly discarded as outside the real draft budget.

## Reproduction

From repository root, use a new output directory for every run:

```sh
python3 Tools/verify-stability.py --output Build/VerificationRuns/background-review-tests-new
python3 docs/audit/2026-10-10-background-review/slow-save-probe.py Build/VerificationRuns/background-review-slow-save-new --expect-fixed
python3 docs/audit/2026-10-10-background-review/rpc-backpressure-probe.py Build/VerificationRuns/background-review-rpc-control-new
python3 docs/audit/2026-10-10-background-review/rpc-backpressure-probe.py Build/VerificationRuns/background-review-rpc-limit-new --near-byte-limit
```

Slow-save injection compiles the unchanged store scheduling and adds one gated call at the temporary copy of `PrivateContentFile.write`. RPC tests compile the unchanged client and framing against a synthetic Python JSONL child. Neither accesses installed agent configurations, sessions or executables. No production user content is read or modified by these probes.

`ResourceCounters.c` compiles with `xcrun clang -Wall -Wextra -Werror -O2`. Supply only verified target PIDs. It checks process start identity and takes 25 readings five seconds apart. CPU percentage is:

```text
100 × delta(cpuMachTicks) × timebaseNumer / timebaseDenom / 1e9 / elapsedSeconds
```

On this Mac the timebase is 125/3. The initial experimental collector labeled raw Mach ticks `cpuNs`; that run is excluded from reported CPU results and remains in `Build/VerificationRuns/background-audit-runtime-20261010/resource-counters.jsonl`. The corrected collector was rebuilt and rerun. Apple's XNU source assigns rusage times from task power counters, whose CPU time fields use Mach units: [rusage assignment](https://github.com/apple-oss-distributions/xnu/blob/main/osfmk/kern/bsd_kern.c), [task power counters](https://github.com/apple-oss-distributions/xnu/blob/main/osfmk/kern/task.c).

Raw compiler/test logs and copied native hosts remain under `Build/VerificationRuns/background-audit-*`. Existing compilation warnings remain. This review did not rerun Release compilation/sanitizers, install a build, change settings, restart Atoll, run real agent integrations, or complete sleep/wake/multi-display/24–72-hour acceptance.
