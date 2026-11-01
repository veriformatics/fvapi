#!/usr/bin/env python3
"""T8 process-isolated RSS/time observations, both builder-retention modes.

Each executable invocation runs decode/normalize/print/release inside a Lean Task.
Ratios are diagnostic observations, not capacity promises or grading thresholds.
"""
import argparse
import csv
from pathlib import Path
import subprocess
import sys
import time

SIZES = {
    'deep': [1024, 4096, 16384, 65536, 1000000],
    'digits': [1024, 4096, 16384, 65536, 1000000],
    'cap-suffix': [1024, 16384, 65536, 65537, 1000000],
    'flat': [1024, 4096, 16384, 65536, 262144],
    'sorted': [128, 512, 2048, 8192, 32768],
    'reverse': [128, 512, 2048, 8192, 32768],
    'prefix': [128, 512, 2048, 8192, 32768],
    'escaped': [1024, 4096, 16384, 65536, 65537],
    'multibyte': [1024, 4096, 16384, 32768, 32769],
}


def run(binary, out):
    out.mkdir(parents=True, exist_ok=True)
    count = 0
    with (out / 'resources.tsv').open('w', newline='') as stream:
        writer = csv.writer(stream, delimiter='\t')
        writer.writerow(['kind', 'n', 'mode', 'wall_s', 'peak_kib', 'task_observation'])
        for kind, sizes in SIZES.items():
            for mode in ['fresh', 'retained']:
                prior = None
                for size in sizes:
                    start = time.monotonic()
                    peak = out / 'resource-peak.txt'
                    try:
                        proc = subprocess.run(['/usr/bin/time', '-f', '%M', '-o', str(peak),
                                               str(binary), 'resource', kind, str(size), mode],
                                              capture_output=True, text=True, timeout=180)
                    except subprocess.TimeoutExpired:
                        print(f'T8: crash/timeout {kind}/{size}/{mode}', file=sys.stderr)
                        return 3
                    elapsed = time.monotonic() - start
                    if proc.returncode:
                        print(proc.stdout + proc.stderr, file=sys.stderr)
                        print(f'T8: {kind}/{size}/{mode} native rc={proc.returncode}', file=sys.stderr)
                        return proc.returncode if proc.returncode in (1, 2) else 3
                    observations = [line for line in proc.stdout.splitlines()
                                    if line.startswith('RESOURCE\t')]
                    if len(observations) != 1 or not peak.is_file():
                        print('setup: missing Task or peak-RSS observation', file=sys.stderr)
                        return 2
                    rss = peak.read_text().strip()
                    peak.unlink()
                    writer.writerow([kind, size, mode, f'{elapsed:.6f}', rss, observations[0]])
                    stream.flush()
                    print(f'T8 {kind} n={size} {mode}: wall={elapsed:.3f}s peak={rss}KiB '
                          + observations[0], flush=True)
                    if prior:
                        n0, t0 = prior
                        ratio = (elapsed / t0) / (size / n0)
                        print(f'T8 ratio/time-per-unit {kind}/{mode}: {ratio:.3f}', flush=True)
                    prior = size, elapsed
                    count += 1
    print(f'T8: {count} Task observations; {out / "resources.tsv"}')
    return 0


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('binary', type=Path)
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    try:
        sys.exit(run(args.binary.resolve(), args.output.resolve()))
    except (OSError, ValueError) as exc:
        print(f'setup: {exc}', file=sys.stderr)
        sys.exit(2)
