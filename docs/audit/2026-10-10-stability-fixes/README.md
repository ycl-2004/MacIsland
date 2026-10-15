# Stability fixes verification — 2026-10-10

Final [verification.json](verification.json) maps the observed local checks and limits. [installation.json](installation.json) identifies the installed app and rollback backups. Device identifiers are omitted from copied XCTest summaries; original xcresult bundles remain local.

- Normal native suite: 327 passed, 0 failures/skips, no xcresult runtime warnings.
- ASAN: 326 passed; TSAN fault suite: 16 passed. Each sanitizer suite retained one CFNetwork priority-inversion warning; no ASAN memory error or TSAN data-race report.
- Python: 7; Agent/RPC synthetic groups: 16; plugin: 7; historical guardian: 4; owned supervisor: 3. All passed.
- Debug and Release builds passed. Release retains 34 deprecation/unused-value/related warnings; actor/Sendable/ownership warning matches are zero. See [release-build.json](release-build.json).
- Prior Stats files: 31 hashes unchanged; only local-volume filtering and architecture documentation have intentional additions. See [baseline-preservation.json](baseline-preservation.json).
- Final installed app: same signing team, strict deep signature verification, matching signed binary/source hash, first normal Quit passed, existing text preserved, and relaunch completed. Short startup samples are recorded separately for each installed revision. This is not a 24–72 hour soak verdict.
- Final startup sampling is in [corrected-startup-summary.json](corrected-startup-summary.json) and [corrected-startup-resources.jsonl](corrected-startup-resources.jsonl). A later closeout process check is recorded independently in installation.json; samples from different PIDs are not combined.

Commands (from repository root):

```sh
python3 Tools/verify-stability.py --output /tmp/atoll-stability-fixes/final-quit-fix
python3 Tools/verify-stability.py --sanitizer address --native-only --output /tmp/atoll-stability-fixes/asan-2
python3 Tools/verify-stability.py --sanitizer thread --native-only --only-tests StabilityHardeningTests --output /tmp/atoll-stability-fixes/tsan-quit-fix
xcodebuild -project DynamicIsland.xcodeproj -scheme DynamicIsland -configuration Release -destination 'platform=macOS' -derivedDataPath Build -disableAutomaticPackageResolution -onlyUsePackageVersionsFromResolvedFile CODE_SIGNING_ALLOWED=NO build
```

Raw stdout/stderr, copied test hosts and xcresult bundles are in the output paths above. The initial ASAN failure is retained in `/tmp/atoll-stability-fixes/asan-1`; [its receipt](first-asan-failure.log.md) explains the corrected asynchronous layout assumption. Final step exit codes and durations are in [final-quit-fix-steps.json](final-quit-fix-steps.json).

No real external Agent CLI was used by regression fixtures. The final installed app uses the user's normal application settings; installation did not directly edit their content or permissions. Installation was added only after the user's explicit request. No commit or push was performed.

The initial installed revision cancelled its first Quit when lazy text restoration changed the snapshot. [That observed failure](first-installed-quit-failure.json) is retained; final normal/TSAN regressions include the corrected readiness boundary. ASAN 326 predates this last fix.

See the [fixes and long-term debugging guide](../../stability-fixes-2026-10-10.md) for the risk table, recovery paths and remaining field acceptance.
