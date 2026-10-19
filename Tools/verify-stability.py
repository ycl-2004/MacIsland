#!/usr/bin/env python3
"""Build and run unit/fixture tests in a copied app with a unique preference domain.

Never launches installed agents or replaces /Applications/Atoll.app. Every command
has a deadline. XCTest host content is also redirected by AppRuntimeEnvironment.
"""
import argparse
import json
import os
from pathlib import Path
import plistlib
import shutil
import signal
import subprocess
import time
import uuid

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--skip-build', action='store_true')
    parser.add_argument('--native-only', action='store_true')
    parser.add_argument('--sanitizer', choices=['address', 'thread'])
    parser.add_argument('--only-tests', help='XCTest class, e.g. StabilityHardeningTests')
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    receipt = args.output or ROOT / 'Build' / 'VerificationRuns' / (time.strftime('%Y%m%d-%H%M%S') + '-' + uuid.uuid4().hex[:8])
    receipt = receipt.resolve()
    receipt.mkdir(parents=True, exist_ok=False)
    steps = []

    def run(label, command, timeout=300, allow_failure=False):
        print(label, flush=True)
        started = time.monotonic()
        with (receipt / (label + '.log')).open('w') as log:
            process = subprocess.Popen(command, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT, start_new_session=True)
            try:
                code = process.wait(timeout=timeout)
            except subprocess.TimeoutExpired:
                os.killpg(process.pid, signal.SIGTERM)
                try:
                    process.wait(timeout=2)
                except subprocess.TimeoutExpired:
                    os.killpg(process.pid, signal.SIGKILL)
                    process.wait(timeout=2)
                code = 124
        steps.append({'name': label, 'exit': code, 'seconds': round(time.monotonic() - started, 2)})
        (receipt / 'steps.json').write_text(json.dumps(steps, indent=2) + '\n')
        if code and not allow_failure:
            raise RuntimeError(f'{label} failed ({code}); see {receipt / (label + ".log")}')
        return code

    xcode = ['xcodebuild', '-project', 'DynamicIsland.xcodeproj', '-scheme', 'DynamicIsland',
             '-configuration', 'Debug', '-destination', 'platform=macOS', '-derivedDataPath', 'Build',
             '-disableAutomaticPackageResolution', '-onlyUsePackageVersionsFromResolvedFile', 'CODE_SIGNING_ALLOWED=NO']
    xcode += ['-enableAddressSanitizer', 'YES' if args.sanitizer == 'address' else 'NO',
              '-enableThreadSanitizer', 'YES' if args.sanitizer == 'thread' else 'NO']
    if not args.skip_build:
        run('build', xcode + ['build-for-testing'], 1800)

    candidates = list((ROOT / 'Build').glob('*.xctestrun')) + list((ROOT / 'Build/Build/Products').glob('*.xctestrun'))
    source = max(candidates, key=lambda p: p.stat().st_mtime)
    hostroot = receipt / 'host'
    hostroot.mkdir()
    shutil.copytree(source.parent / 'Debug', hostroot / 'Debug', symlinks=True)
    app = hostroot / 'Debug/Atoll.app'
    info = app / 'Contents/Info.plist'
    metadata = plistlib.loads(info.read_bytes())
    identifier = 'app.atoll.verification.' + uuid.uuid4().hex
    metadata['CFBundleIdentifier'] = identifier
    metadata['CFBundleName'] = 'YC Island Tests'
    metadata['CFBundleDisplayName'] = 'YC Island Tests'
    info.write_bytes(plistlib.dumps(metadata))
    run('sign-host', ['codesign', '--force', '--deep', '--sign', '-', str(app)])
    configuration = plistlib.loads(source.read_bytes())
    for test_configuration in configuration['TestConfigurations']:
        test_configuration['TestTargets'] = [target for target in test_configuration['TestTargets']
                                               if target.get('BlueprintName') == 'DynamicIslandTests']
        for target in test_configuration['TestTargets']:
            target['TestHostBundleIdentifier'] = identifier
            target['ParallelizationEnabled'] = False
            target['TestTimeoutsEnabled'] = True
            target['DefaultTestExecutionTimeAllowance'] = 60
            target['MaximumTestExecutionTimeAllowance'] = 120
            if args.only_tests:
                target['OnlyTestIdentifiers'] = [args.only_tests]
    assert any(c['TestTargets'] for c in configuration['TestConfigurations']), 'No native unit target found'
    testfile = hostroot / 'DynamicIsland.xctestrun'
    testfile.write_bytes(plistlib.dumps(configuration))
    resultpath = receipt / 'native.xcresult'
    native_status = None
    try:
        native_status = run('native', ['xcodebuild', 'test-without-building', '-xctestrun', str(testfile),
                      '-destination', 'platform=macOS', '-resultBundlePath', str(resultpath),
                      '-parallel-testing-enabled', 'NO'], 1200, allow_failure=True)
    finally:
        # Isolated preferences alone are not enough: launching the host also
        # registers its one-off bundle ID with Launch Services. Keep results,
        # unregister every host, and remove successful hosts to stop rediscovery.
        # The whole copied products folder goes (~85 MB per run, including the
        # unused UI-test runner app); the xcresult lives outside it.
        subprocess.run(['defaults', 'delete', identifier], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        (Path.home() / 'Library/Preferences' / (identifier + '.plist')).unlink(missing_ok=True)
        run('unregister-host', ['/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister', '-u', str(app)])
        if native_status == 0:
            shutil.rmtree(hostroot)
        (receipt / 'host-cleanup.json').write_text(json.dumps({
            'identifier': identifier, 'app': str(app), 'unregistered': True,
            'hostRemoved': not hostroot.exists(), 'resultsRetained': resultpath.exists()
        }, indent=2) + '\n')
    run('native-summary', ['xcrun', 'xcresulttool', 'get', 'test-results', 'summary', '--path', str(resultpath), '--format', 'json'])
    if native_status:
        raise RuntimeError(f'Native tests failed ({native_status}); see {receipt / "native-summary.log"}')
    if not args.native_only:
        run('python', ['python3', '-m', 'unittest', 'tests.test_privacy_configuration', 'tests.test_timer_lifecycle'])
        sources = sorted((ROOT / 'DynamicIsland/managers/Agents').glob('*.swift'))
        for folder in ['Sources', 'Terminals']:
            sources += sorted((ROOT / 'DynamicIsland/managers/Agents' / folder).glob('*.swift'))
        sources += [ROOT / 'DynamicIsland/utils' / (name + '.swift') for name in ['AtollTemporaryFiles', 'PipeReadWaiter', 'PrivateContentFile', 'LatestSnapshotWriter']]
        sources += [ROOT / 'DynamicIsland/helpers/AppRuntimeEnvironment.swift', ROOT / 'tests/AgentConversationRegression.swift']
        agent = receipt / 'agent-regression'
        run('agent-build', ['xcrun', 'swiftc', '-swift-version', '5', '-module-cache-path', str(receipt / 'swift-cache'), *map(str, sources), '-o', str(agent)])
        run('agent', [str(agent), str(ROOT / 'tests/agent-rpc-fixture')])
        run('plugin', ['node', 'tests/AgentPluginQueueAudit.mjs'])
        run('guardian', ['python3', 'tests/OSDGuardianRegression.py'])
        run('supervisor', ['python3', 'tests/ProcessSupervisorRegression.py'])
    print(f'PASS: {receipt}', flush=True)


if __name__ == '__main__':
    main()
