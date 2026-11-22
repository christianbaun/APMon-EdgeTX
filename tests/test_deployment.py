# =============================================================================
# APMon - EdgeTX Monitor for ArduPilot
# File: tests/test_deployment.py
# Purpose: Verify display selection, deployment preview and SD-card file isolation.
# Project version: 0.8.0
# Updated: 2026-11-21
# Authors: Christian Baun
# Development assistance: OpenAI Codex CLI (code, tests and documentation)
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
from zipfile import ZipFile

import deploy
from package_sd import COLOR_LOGO, SD_VERSION, SW_TOOLS, build_all, files_for, source_for


class DeploymentTests(unittest.TestCase):
    def test_display_file_sets(self):
        sw, color = set(files_for('sw')), set(files_for('color'))
        shared = {Path('SCRIPTS/APMON/config.lua'), Path('SCRIPTS/APMON/pass.lua'),
                  Path('SCRIPTS/APMON/diagnostics.lua'),
                  Path('SCRIPTS/APMON/armed_summary.lua'),
                  Path('SCRIPTS/APMON/project.lua'), SD_VERSION}
        self.assertTrue(shared <= sw & color)
        self.assertIn(Path('SCRIPTS/TELEMETRY/APMon.lua'), sw)
        self.assertNotIn(Path('WIDGETS/APMon/main.lua'), sw)
        self.assertIn(Path('WIDGETS/APMon/main.lua'), color)
        self.assertIn(COLOR_LOGO, color)
        self.assertNotIn(COLOR_LOGO, sw)
        self.assertTrue(SW_TOOLS.issubset(sw))
        self.assertTrue(SW_TOOLS.isdisjoint(color))
        self.assertFalse(any('TELEMETRY' in p.parts for p in color))
        with self.assertRaises(ValueError):
            files_for('unknown')

    def test_logo_only_in_color_archive(self):
        with tempfile.TemporaryDirectory() as tmp, contextlib.redirect_stdout(io.StringIO()):
            output = Path(tmp)
            build_all(output)
            with ZipFile(output / 'APMon-COLOR.zip') as archive:
                self.assertEqual(archive.read(SD_VERSION.as_posix()), (deploy.ROOT / 'VERSION').read_bytes())
                self.assertEqual(archive.read(COLOR_LOGO.as_posix()),
                                 (deploy.ROOT / 'SD' / COLOR_LOGO).read_bytes())
            with ZipFile(output / 'APMon-SW.zip') as archive:
                self.assertEqual(archive.read(SD_VERSION.as_posix()), (deploy.ROOT / 'VERSION').read_bytes())
                self.assertNotIn(COLOR_LOGO.as_posix(), archive.namelist())

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
                if display == 'color':
                    unrelated = (card / COLOR_LOGO).with_suffix('.luac')
                    unrelated.parent.mkdir(parents=True)
                    unrelated.write_bytes(b'unrelated Lua cache')
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
                    self.assertEqual((card / rel).read_bytes(), source_for(rel).read_bytes())
                self.assertFalse(compiled.exists())
                self.assertEqual(preference.read_text(), 'de')
                self.assertEqual(other.read_text(), 'unrelated script')
                self.assertEqual(model.read_text(), 'model settings')
                if display == 'sw':
                    self.assertFalse((card / 'WIDGETS').exists())
                else:
                    self.assertFalse((card / 'SCRIPTS/TELEMETRY').exists())
                    self.assertEqual(unrelated.read_bytes(), b'unrelated Lua cache')


if __name__ == '__main__':
    unittest.main()
