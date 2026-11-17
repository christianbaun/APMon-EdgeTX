# =============================================================================
# APMon - EdgeTX Monitor for ArduPilot
# File: tests/test_deployment.py
# Purpose: Verify display selection, deployment preview and SD-card file isolation.
# Project version: 0.1.0
# Updated: 2026-11-17
# Authors: APMon contributors
# Development assistance: OpenAI Codex CLI (code, tests and documentation)
# Copyright (c) 2026 APMon contributors
# SPDX-License-Identifier: Apache-2.0
# License: Apache License, Version 2.0 (https://www.apache.org/licenses/LICENSE-2.0)
# See LICENSE in the repository or SCRIPTS/APMON/LICENSE.txt in SD packages.
# =============================================================================

import contextlib
import io
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

import deploy
from package_sd import files_for


class DeploymentTests(unittest.TestCase):
    def test_display_file_sets(self):
        sw, color = set(files_for('sw')), set(files_for('color'))
        shared = {Path('SCRIPTS/APMON/config.lua'), Path('SCRIPTS/APMON/pass.lua')}
        self.assertTrue(shared <= sw & color)
        self.assertIn(Path('SCRIPTS/TELEMETRY/APMon.lua'), sw)
        self.assertNotIn(Path('WIDGETS/APMon/main.lua'), sw)
        self.assertIn(Path('WIDGETS/APMon/main.lua'), color)
        self.assertFalse(any('TELEMETRY' in p.parts for p in color))
        with self.assertRaises(ValueError):
            files_for('unknown')

    def test_display_is_required(self):
        with patch.object(sys, 'argv', ['deploy.py']), contextlib.redirect_stderr(io.StringIO()):
            with self.assertRaises(SystemExit) as error:
                deploy.main()
        self.assertEqual(error.exception.code, 2)

    def test_preview_and_apply_for_each_display(self):
        for display in ('sw', 'color'):
            with self.subTest(display=display), tempfile.TemporaryDirectory() as tmp:
                card = Path(tmp)
                for folder in ('MODELS', 'RADIO', 'SCRIPTS/APMON'):
                    (card / folder).mkdir(parents=True)
                config = card / 'SCRIPTS/APMON/config.lua'
                config.write_text('old config')
                compiled = config.with_suffix('.luac')
                compiled.write_bytes(b'old bytecode')
                preference = card / 'SCRIPTS/APMON/mono.cfg'
                preference.write_text('de')
                other = card / 'SCRIPTS/other.lua'
                other.write_text('unrelated script')
                model = card / 'MODELS/test.yml'
                model.write_text('model settings')
                args = ['deploy.py', '--display', display, '--sd', tmp]
                with patch.object(sys, 'argv', args), contextlib.redirect_stdout(io.StringIO()), \
                        patch.object(deploy.subprocess, 'run') as run, \
                        patch.object(deploy, 'build_all') as build:
                    deploy.main()
                    run.assert_not_called()
                    build.assert_not_called()
                self.assertEqual(config.read_text(), 'old config')
                self.assertTrue(compiled.exists())
                with patch.object(sys, 'argv', args + ['--apply']), \
                        contextlib.redirect_stdout(io.StringIO()), \
                        patch.object(deploy.subprocess, 'run') as run, \
                        patch.object(deploy, 'build_all') as build:
                    deploy.main()
                    build.assert_called_once()
                    self.assertEqual(run.call_count, 2)  # Lua validation and sync
                for rel in files_for(display):
                    self.assertEqual((card / rel).read_bytes(), (deploy.ROOT / 'SD' / rel).read_bytes())
                self.assertFalse(compiled.exists())
                self.assertEqual(preference.read_text(), 'de')
                self.assertEqual(other.read_text(), 'unrelated script')
                self.assertEqual(model.read_text(), 'model settings')
                if display == 'sw':
                    self.assertFalse((card / 'WIDGETS').exists())
                else:
                    self.assertFalse((card / 'SCRIPTS/TELEMETRY').exists())


if __name__ == '__main__':
    unittest.main()
