#!/usr/bin/env python3
"""Report Atoll development caches. Default is read-only; --apply prunes old receipts/results only."""
from pathlib import Path
import argparse
import json
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[1]

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--apply', action='store_true', help='Remove reported old test results/backups, retaining the newest 3/2')
    args = parser.parse_args()
    build = ROOT / 'Build'
    report = []
    for parent, keep, pattern in [(build/'Logs'/'Test', 3, '*.xcresult'), (build/'InstalledBackups', 2, '*')]:
        # Only complete build-owned results or installation receipts qualify.
        entries = [p for p in parent.glob(pattern) if p.is_dir() and not p.is_symlink()
                   and (p.suffix == '.xcresult' or (p/'installation.json').is_file())]
        entries.sort(key=lambda p: p.stat().st_mtime, reverse=True)
        for path in entries[keep:]:
            size = int(subprocess.check_output(['/usr/bin/du', '-sk', str(path)], text=True).split()[0])
            report.append({'path': str(path.relative_to(ROOT)), 'allocated_KiB': size, 'action': 'removed' if args.apply else 'candidate'})
            if args.apply:
                assert path.resolve().is_relative_to(build.resolve())
                shutil.rmtree(path)
    print(json.dumps({'mode': 'apply' if args.apply else 'dry-run', 'kept_test_results': 3, 'kept_installed_backups': 2,
                      'candidates': report, 'untouched': ['SourcePackages', 'current builds', 'app content', 'git data']}, indent=2))

if __name__ == '__main__':
    main()
