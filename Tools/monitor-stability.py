#!/usr/bin/env python3
"""Read-only bounded resource sampling for an explicitly supplied PID.

No command arguments, file names, conversation data or credentials are collected.
Stops if the PID disappears or is reused. Keeps at most two 8 MB JSONL files.
"""
import argparse
import json
import os
from pathlib import Path
import subprocess
import time


def command(*args):
    result = subprocess.run(args, capture_output=True, text=True, timeout=3)
    return result.stdout.strip() if result.returncode == 0 else ''


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--pid', required=True, type=int)
    parser.add_argument('--hours', type=float, default=24)
    parser.add_argument('--interval', type=float, default=10)
    parser.add_argument('--output', required=True, type=Path)
    args = parser.parse_args()
    if args.pid <= 1 or not 0 < args.hours <= 72 or args.interval < 1:
        parser.error('Use PID > 1, 0 < hours <= 72, interval >= 1 second')
    args.output.mkdir(parents=True, exist_ok=True)
    args.output.chmod(0o700)
    identity = command('/bin/ps', '-p', str(args.pid), '-o', 'lstart=')
    if not identity:
        parser.error('PID is not running')
    target = args.output / 'resources.jsonl'
    previous = args.output / 'resources.previous.jsonl'
    deadline = time.monotonic() + args.hours * 3600
    samples = 0
    reason = 'duration'
    try:
        while time.monotonic() < deadline:
            start = time.monotonic()
            if command('/bin/ps', '-p', str(args.pid), '-o', 'lstart=') != identity:
                reason = 'process ended or PID reused'
                break
            stats = command('/bin/ps', '-p', str(args.pid), '-o', '%cpu=,rss=,etime=').split()
            if len(stats) < 3:
                reason = 'process unavailable'
                break
            descriptors = command('/usr/sbin/lsof', '-nP', '-a', '-p', str(args.pid), '-Ff')
            children = command('/usr/bin/pgrep', '-P', str(args.pid)).splitlines()
            row = {'unixTime': time.time(), 'pid': args.pid, 'cpuPercent': float(stats[0]),
                   'rssKB': int(stats[1]), 'elapsed': stats[2], 'children': len(children),
                   'openFDs': sum(line.startswith('f') and line[1:].isdigit() for line in descriptors.splitlines()) if descriptors else None}
            if target.exists() and target.stat().st_size >= 8 * 1024 * 1024:
                os.replace(target, previous)
            fd = os.open(target, os.O_CREAT | os.O_APPEND | os.O_WRONLY, 0o600)
            with os.fdopen(fd, 'a') as log:
                log.write(json.dumps(row) + '\n')
            samples += 1
            time.sleep(min(max(0, args.interval - (time.monotonic() - start)), max(0, deadline - time.monotonic())))
    except KeyboardInterrupt:
        reason = 'interrupted'
    except subprocess.TimeoutExpired:
        reason = 'resource query timed out'
    (args.output / 'summary.json').write_text(json.dumps({'pid': args.pid, 'samples': samples, 'stopped': reason}, indent=2) + '\n')
    print(f'{samples} samples; {reason}; {args.output}')


if __name__ == '__main__':
    main()
