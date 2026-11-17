#!/usr/bin/env python3
# =============================================================================
# APMon - EdgeTX Monitor for ArduPilot
# File: deploy.py
# Purpose: Preview or deploy APMon files to a mounted SD card after running validation.
# Project version: 0.1.0
# Updated: 2026-11-17
# Authors: APMon contributors
# Development assistance: OpenAI Codex CLI (code, tests and documentation)
# Copyright (c) 2026 APMon contributors
# SPDX-License-Identifier: Apache-2.0
# License: Apache License, Version 2.0 (https://www.apache.org/licenses/LICENSE-2.0)
# See LICENSE in the repository or SCRIPTS/APMON/LICENSE.txt in SD packages.
# =============================================================================

"""Deploy only APMon-owned files to a mounted EdgeTX SD card."""
import argparse
from pathlib import Path
import shutil
import subprocess
import sys
from package_sd import files_for, build_all

ROOT = Path(__file__).resolve().parent


def radio_card(path):
    return all((path / name).is_dir() for name in ('MODELS', 'RADIO', 'SCRIPTS'))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--sd', type=Path, help='Mounted SD-card root')
    parser.add_argument('--apply', action='store_true', help='Copy files (default: preview)')
    parser.add_argument('--display', choices=('sw', 'color'), required=True,
                        help='sw: monochrome telemetry script; color: color LCD widget')
    args = parser.parse_args()
    if args.sd:
        target = args.sd.resolve()
        if not radio_card(target):
            parser.error('Target must contain MODELS, RADIO and SCRIPTS directories')
    else:
        candidates = set()
        for base in (Path('/run/media'), Path('/media'), Path('/mnt')):
            for pattern in ('*', '*/*'):
                for path in base.glob(pattern):
                    if radio_card(path):
                        candidates.add(path.resolve())
        if len(candidates) != 1:
            parser.error('Connect exactly one EdgeTX SD card, or specify --sd PATH')
        target = candidates.pop()

    files = files_for(args.display)
    # Resolve every destination before writing; reject redirected paths.
    for rel in files:
        for dest in (target / rel, (target / rel).with_suffix('.luac')):
            if not dest.resolve().is_relative_to(target):
                parser.error('Destination escapes SD card: ' + str(dest))
    print('SD card:', target)
    for rel in files:
        print('Copy:', rel)
        compiled = (target / rel).with_suffix('.luac')
        if compiled.exists():
            print('Remove compiled cache:', compiled.relative_to(target))
    if not args.apply:
        print('Preview only. Add --apply to run tests and deploy.')
        return

    subprocess.run([sys.executable, str(ROOT / 'tests/run.py')], cwd=ROOT, check=True)
    build_all()
    for rel in files:
        source, dest = ROOT / 'SD' / rel, target / rel
        dest.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(source, dest)
        if source.read_bytes() != dest.read_bytes():
            raise RuntimeError('Verification failed: ' + str(dest))
        dest.with_suffix('.luac').unlink(missing_ok=True)
    subprocess.run(['sync'], check=True)
    print('Deployment verified. Eject the SD card safely, then restart the radio.')


if __name__ == '__main__':
    try:
        main()
    except (OSError, RuntimeError, subprocess.CalledProcessError) as exc:
        sys.exit('Deployment failed: ' + str(exc))
