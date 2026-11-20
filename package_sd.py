# =============================================================================
# APMon - EdgeTX Monitor for ArduPilot
# File: package_sd.py
# Purpose: Build and verify separate monochrome and color SD-card distribution archives.
# Project version: 0.2.0
# Updated: 2026-11-20
# Authors: APMon contributors
# Development assistance: OpenAI Codex CLI (code, tests and documentation)
# Copyright (c) 2026 APMon contributors
# SPDX-License-Identifier: Apache-2.0
# License: Apache License, Version 2.0 (https://www.apache.org/licenses/LICENSE-2.0)
# See LICENSE in the repository or SCRIPTS/APMON/LICENSE.txt in SD packages.
# =============================================================================

"""Build verified SD-card archives for each supported display type."""
from pathlib import Path
import subprocess
import sys
from zipfile import ZipFile, ZIP_DEFLATED

ROOT = Path(__file__).resolve().parent
COLOR_LOGO = Path('WIDGETS/APMon/logo.png')


def files_for(display):
    files = sorted(p.relative_to(ROOT / 'SD') for p in (ROOT / 'SD').rglob('*.lua'))
    if display == 'sw':
        return [p for p in files if p.parts[0] == 'SCRIPTS']
    if display == 'color':
        return sorted([p for p in files if 'TELEMETRY' not in p.parts] + [COLOR_LOGO])
    raise ValueError('Display must be sw or color')


def build_all(output_dir=ROOT):
    for display, name in [('sw', 'APMon-SW.zip'), ('color', 'APMon-COLOR.zip')]:
        files = files_for(display)
        path = output_dir / name
        with ZipFile(path, 'w', ZIP_DEFLATED) as archive:
            for rel in files:
                archive.write(ROOT / 'SD' / rel, rel)
            archive.write(ROOT / 'LICENSE', 'SCRIPTS/APMON/LICENSE.txt')
        with ZipFile(path) as archive:
            assert archive.testzip() is None
            for rel in files:
                assert archive.read(rel.as_posix()) == (ROOT / 'SD' / rel).read_bytes()
            assert archive.read('SCRIPTS/APMON/LICENSE.txt') == (ROOT / 'LICENSE').read_bytes()
        print('Verified:', name)


if __name__ == '__main__':
    subprocess.run([sys.executable, str(ROOT / 'tests/run.py')], cwd=ROOT, check=True)
    build_all()
