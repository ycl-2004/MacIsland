#!/usr/bin/env python3
"""Embed source identity; no paths, user data, or build timestamps in the bundle."""
import hashlib
import json
import os
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]


def git(*args):
    return subprocess.check_output(['git', *args], cwd=ROOT, timeout=10)


def main():
    paths = git('ls-files', '-co', '--exclude-standard', '-z', '--',
                'DynamicIsland', 'DynamicIslandTests', 'DynamicIsland.xcodeproj', 'Tools', 'mediaremote-adapter', 'tests').split(b'\0')
    digest = hashlib.sha256()
    for raw in sorted(set(paths)):
        if not raw:
            continue
        relative = os.fsdecode(raw)
        path = ROOT / relative
        if path.is_file():
            digest.update(raw + b'\0')
            digest.update(hashlib.sha256(path.read_bytes()).digest())
    resolved = ROOT / 'DynamicIsland.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved'
    data = {
        'commit': git('rev-parse', 'HEAD').decode().strip(),
        'dirty': str(bool(git('status', '--porcelain', '--untracked-files=normal').strip())).lower(),
        'sourceSHA256': digest.hexdigest(),
        'packagesSHA256': hashlib.sha256(resolved.read_bytes()).hexdigest(),
        'xcode': os.environ.get('XCODE_VERSION_ACTUAL', 'unknown'),
        'sdk': os.environ.get('SDK_NAME', 'unknown'),
        'configuration': os.environ.get('CONFIGURATION', 'unknown'),
        'version': os.environ.get('MARKETING_VERSION', 'unknown'),
        'build': os.environ.get('CURRENT_PROJECT_VERSION', 'unknown'),
    }
    destination = Path(os.environ['TARGET_BUILD_DIR']) / os.environ['UNLOCALIZED_RESOURCES_FOLDER_PATH'] / 'BuildInfo.json'
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_text(json.dumps(data, indent=2, sort_keys=True) + '\n')


if __name__ == '__main__':
    main()
