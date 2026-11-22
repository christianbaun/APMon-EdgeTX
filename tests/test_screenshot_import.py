# =============================================================================
# APMon - EdgeTX Monitor for ArduPilot
# File: tests/test_screenshot_import.py
# Purpose: Check screenshot selection, pixel conversion, naming and safe import.
# Project version: 0.7.0
# Updated: 2026-11-20
# Authors: Christian Baun
# Development assistance: OpenAI Codex CLI (code, tests and documentation)
# SPDX-License-Identifier: Apache-2.0
# See LICENSE in the repository.
# =============================================================================

import contextlib
from datetime import datetime
import io
import os
from pathlib import Path
import struct
import sys
import tempfile
import unittest
from unittest.mock import patch

import import_screenshots

try:
    from PIL import Image
except ImportError:
    Image = None


@unittest.skipIf(Image is None, 'Pillow is not installed')
class ScreenshotImportTests(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        self.root = Path(temp.name) / 'repo'
        self.root.mkdir()
        (self.root / 'VERSION').write_text('0.2.0\n')
        self.card = Path(temp.name) / 'radio'
        self.files = self.card / 'SCREENSHOTS'
        for folder in ('MODELS', 'RADIO', 'SCRIPTS', 'SCREENSHOTS'):
            (self.card / folder).mkdir(parents=True)
        self.output = self.root / 'images' / 'screenshots'

    def run_import(self, *args):
        stdout = io.StringIO()
        with patch.object(import_screenshots, 'ROOT', self.root), \
                patch.object(sys, 'argv', ['import_screenshots.py', '--sd', str(self.card), *args]), \
                contextlib.redirect_stdout(stdout):
            import_screenshots.main()
        return stdout.getvalue()

    def make_sw_bmp(self, name):
        # The real 128x64 EdgeTX BMP has a 4-bit grayscale palette.
        pixels = bytes([0xF0]) * (128 * 64 // 2)
        offset = 14 + 40 + 16 * 4
        file_header = struct.pack('<2sIHHI', b'BM', offset + len(pixels), 0, 0, offset)
        info_header = struct.pack('<IiiHHIIiiII', 40, 128, 64, 1, 4, 0, len(pixels), 0, 0, 16, 0)
        palette = b''.join(bytes((v, v, v, 0)) for v in range(0, 256, 17))
        path = self.files / name
        path.write_bytes(file_header + info_header + palette + pixels)
        return path

    def test_preview_then_import_all_new_edge_tx_bmps(self):
        older = self.make_sw_bmp('screen-2026-11-19-083000.bmp')
        capture = self.make_sw_bmp('screen-2026-11-20-090305.BMP')
        os.utime(older, (capture.stat().st_mtime + 60,) * 2)
        original = capture.read_bytes()
        args = ('--display', 'sw', '--radio', 'GX12', '--view', 'overview', '--lang', 'de', '--scale', '4')
        filename = 'apmon-sw-gx12-overview-de-v0.2.0-2026-11-20-090305-4x.png'
        older_filename = 'apmon-sw-gx12-overview-de-v0.2.0-2026-11-19-083000-4x.png'
        preview = self.run_import(*args)
        self.assertLess(preview.index(filename), preview.index(older_filename))
        self.assertIn('Preview only', preview)
        self.assertFalse(self.output.exists())
        self.assertIn('Imported 2 screenshot', self.run_import(*args, '--apply'))
        with Image.open(self.output / filename) as png:
            self.assertEqual(png.size, (512, 256))
            self.assertEqual(png.getpixel((3, 0)), (255, 255, 255))
            self.assertEqual(png.getpixel((4, 0)), (0, 0, 0))
        self.assertEqual(capture.read_bytes(), original)
        self.assertIn('Imported 0 screenshot', self.run_import(*args, '--apply'))

    def test_imports_only_new_captures_when_metadata_changes(self):
        old = self.make_sw_bmp('screen-2026-11-20-090305.bmp')
        self.run_import('--display', 'sw', '--view', 'overview', '--lang', 'de',
                        '--scale', '4', '--file', old.name, '--apply')
        # Both new files have the old capture's timestamp or pixels, but not both.
        Image.new('RGB', (128, 64), 'red').save(old.with_suffix('.png'))
        self.make_sw_bmp('screen-2026-11-20-090306.bmp')
        args = ('--display', 'sw', '--view', 'flight', '--lang', 'en', '--version', '0.2.1', '--apply')
        output = self.run_import(*args)
        self.assertIn('Already imported: ' + old.name, output)
        self.assertIn('Imported 2 screenshot', output)
        self.assertEqual(len(list(self.output.glob('*.png'))), 3)
        self.assertIn('Imported 0 screenshot', self.run_import(*args))

    def test_empty_folder_is_a_no_op(self):
        self.assertIn('No BMP or PNG screenshots found',
                      self.run_import('--display', 'sw', '--view', 'menu', '--lang', 'de', '--apply'))
        self.assertFalse(self.output.exists())

    def test_inventory_and_mtime_for_renamed_capture(self):
        capture = self.files / 'menu.png'
        Image.new('RGB', (480, 320), (12, 20, 30)).save(capture)
        timestamp = datetime(2026, 11, 20, 14, 15, 16).timestamp()
        os.utime(capture, (timestamp, timestamp))
        (self.files / 'readme.txt').write_text('not a capture')
        (self.files / 'linked.png').symlink_to(capture)
        inventory = self.run_import('--list')
        self.assertIn('2026-11-20 14:15:16  menu.png  (file modification time)', inventory)
        self.assertNotIn('readme.txt', inventory)
        self.assertNotIn('linked.png', inventory)
        self.assertFalse(self.output.exists())
        self.run_import('--file', 'menu.png', '--display', 'color', '--radio', 'gx15',
                        '--view', 'menu', '--language', 'en', '--version', 'v0.2.1-rc.1', '--apply')
        with Image.open(self.output / 'apmon-color-gx15-menu-en-v0.2.1-rc.1-2026-11-20-141516.png') as png:
            self.assertEqual(png.size, (480, 320))
            self.assertEqual(png.getpixel((0, 0)), (12, 20, 30))

    def test_batch_uses_suffixes_without_overwriting_or_duplicating(self):
        first = self.make_sw_bmp('screen-2026-11-20-090305.bmp')
        second = first.with_suffix('.png')
        Image.new('RGB', (128, 64), 'red').save(second)
        args = ('--display', 'sw', '--view', 'messages', '--lang', 'en', '--apply')
        self.run_import(*args, '--file', first.name)
        filename = self.output / 'apmon-sw-messages-en-v0.2.0-2026-11-20-090305.png'
        original = filename.read_bytes()
        batch = ('--file', first.name, '--file', second.name)
        self.assertIn('Imported 1 screenshot', self.run_import(*args, *batch))
        self.assertTrue(filename.with_stem(filename.stem + '-02').exists())
        self.assertEqual(filename.read_bytes(), original)
        self.assertIn('Imported 0 screenshot', self.run_import(*args, *batch))
        self.assertEqual(len(list(self.output.iterdir())), 2)

    def test_rejects_mislabeled_display_path_traversal_and_redirected_destination(self):
        capture = self.make_sw_bmp('screen-2026-11-20-090305.bmp')
        with self.assertRaisesRegex(ValueError, 'COLOR expects'):
            self.run_import('--display', 'color', '--view', 'menu', '--lang', 'en', '--apply')
        self.assertFalse(self.output.exists())
        args = ('--display', 'sw', '--view', 'menu', '--lang', 'de', '--apply')
        with self.assertRaises(SystemExit), contextlib.redirect_stderr(io.StringIO()):
            self.run_import(*args, '--file', '../SCREENSHOTS/' + capture.name)
        self.output.parent.symlink_to(self.files, target_is_directory=True)
        with self.assertRaisesRegex(ValueError, 'Refusing redirected'):
            self.run_import(*args)
        self.assertEqual(list(self.files.iterdir()), [capture])
