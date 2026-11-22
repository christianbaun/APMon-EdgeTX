#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Run scripted APMon checks in a host LCD simulator and render GIF demos."""

import argparse
from functools import lru_cache
import os
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parent
PROFILES = ('sw-128x64', 'sw-212x64', 'color-440x252', 'color-480x320', 'color-800x480')
LANGUAGES = ('en', 'de')


def replay(profile, lang):
    env = dict(os.environ, APMON_PROFILE=profile, APMON_LANG=lang)
    result = subprocess.run(
        [sys.executable, str(ROOT / 'tests/run.py'), 'tests/simulator.lua'],
        cwd=ROOT, env=env, capture_output=True, text=True, encoding='utf-8',
    )
    if result.returncode:
        raise RuntimeError(result.stderr.strip() or 'Lua replay failed')

    frames, commands = [], []
    for line in result.stdout.splitlines():
        kind, *args = line.split('\t')
        if kind == 'frame':
            ms, key, caption = args
            frames.append((int(ms), key, caption, commands))
            commands = []
        elif kind == 'done':
            if len(frames) != int(args[0]) or commands or not frames:
                raise RuntimeError('Incomplete Lua replay')
            return frames
        elif kind == 'touch':
            frames[-1][3].append((kind, args))
        else:
            commands.append((kind, args))
    raise RuntimeError('Lua replay did not complete')


def render_gif(frames, profile, lang, destination, font_path=None):
    try:
        from PIL import Image, ImageDraw, ImageFont
    except ImportError as exc:
        raise RuntimeError('Install Pillow >= 10.1 or run with --check') from exc

    display, resolution = profile.split('-', 1)
    width, height = map(int, resolution.split('x'))
    scale = 3 if display == 'sw' else 1
    w, h = width * scale, height * scale
    margin, banner = 12, 60

    for name in (font_path,) if font_path else ('DejaVuSans.ttf', 'LiberationSans-Regular.ttf', 'Arial.ttf'):
        try:
            ImageFont.truetype(name, size=16)
            break
        except OSError:
            continue
    else:
        raise RuntimeError('Install DejaVu Sans or pass --font with a Unicode TrueType font')

    @lru_cache(maxsize=None)
    def font(size):
        return ImageFont.truetype(name, size=size)

    @lru_cache(maxsize=256)
    def glyphs(value, width_px, height_px):
        """Approximate the glyphs while honoring the Lua LCD layout metrics."""
        face = font(max(9, height_px))
        x0, y0, x1, y1 = face.getbbox(value)
        if x1 <= x0 or y1 <= y0:
            return Image.new('L', (width_px, height_px))
        mask = Image.new('L', (x1 - x0, y1 - y0))
        ImageDraw.Draw(mask).text((-x0, -y0), value, font=face, fill=255)
        box = mask.getbbox()
        if box is None:
            return Image.new('L', (width_px, height_px))
        fitted_height = max(1, min(y1 - y0, height_px - scale))
        glyph = mask.resize((width_px, fitted_height), Image.Resampling.LANCZOS)
        patch = Image.new('L', (width_px, height_px))
        patch.paste(glyph, (0, (height_px - fitted_height) // 2))
        return patch

    def rgb(value):
        return (value >> 16 & 255, value >> 8 & 255, value & 255)

    with Image.open(ROOT / 'SD/WIDGETS/APMon/logo.png') as png:
        logo = png.convert('RGBA').resize((32, 32), Image.Resampling.LANCZOS)
    images, delays = [], []
    for i, (ms, key, caption, commands) in enumerate(frames, 1):
        panel = Image.new('RGB', (w, h), 'black')
        draw = ImageDraw.Draw(panel)
        for kind, args in commands:
            if kind == 'text':
                x, y, tw, th = (int(v) * scale for v in args[:4])
                ink, inverse = int(args[4]), int(args[5])
                if tw <= 0:
                    continue
                bounds = (x, y, x + tw, y + th)
                if inverse:
                    panel.paste('white', bounds)
                panel.paste(rgb(ink), bounds, glyphs(args[6], tw, th))
            elif kind == 'rect':
                x, y, rw, rh = (int(v) * scale for v in args[:4])
                if rw > 0 and rh > 0:
                    draw.rectangle((x, y, x + rw - 1, y + rh - 1), fill=rgb(int(args[4])))
            elif kind == 'line':
                draw.line(tuple(int(v) * scale for v in args[:4]), fill=rgb(int(args[4])), width=scale)
            elif kind == 'logo':
                panel.paste(logo, tuple(map(int, args)), logo)
            elif kind == 'touch':
                x, y = map(int, args)
                draw.ellipse((x - 8, y - 8, x + 8, y + 8), outline='#ffc046', width=2)
            else:
                raise RuntimeError(f'Unexpected LCD command: {kind}')

        canvas = Image.new('RGB', (w + 2 * margin, h + banner + margin), '#171f29')
        canvas.paste(panel, (margin, margin))
        draw = ImageDraw.Draw(canvas)
        qualifier = 'Synthetische Telemetrie' if lang == 'de' else 'Synthetic telemetry'
        draw.text((margin, margin + h + 6), f'{profile.upper()}  ·  {qualifier}  ·  {i}/{len(frames)}',
                  font=font(13), fill='#9bb0c5')
        label = f'{key}: {caption}' if key else caption
        size = 18
        while font(size).getlength(label) > w and size > 10:
            size -= 1
        draw.text((margin, margin + h + 29), label, font=font(size), fill='#eef7ff')
        images.append(canvas)
        delays.append(ms)

    images[0].save(destination, save_all=True, append_images=images[1:],
                   duration=delays, loop=0, disposal=2)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--profile', choices=PROFILES, action='append', help='repeat to select several displays')
    parser.add_argument('--lang', choices=LANGUAGES, action='append', help='repeat to select several languages')
    parser.add_argument('--check', action='store_true', help='run assertions without generating GIFs or using Pillow')
    parser.add_argument('--output-dir', type=Path, default=ROOT / 'simulator-output')
    parser.add_argument('--font', help='optional Unicode TrueType font path')
    args = parser.parse_args()
    for profile in args.profile or PROFILES:
        for lang in args.lang or LANGUAGES:
            try:
                frames = replay(profile, lang)
                if not args.check:
                    args.output_dir.mkdir(parents=True, exist_ok=True)
                    path = args.output_dir / f'apmon-{profile}-{lang}.gif'
                    render_gif(frames, profile, lang, path, args.font)
                print(f'OK: {profile} {lang}, {len(frames)} scenes' + ('' if args.check else f' → {path}'))
            except (OSError, RuntimeError, TypeError, ValueError) as exc:
                parser.exit(1, f'{profile} {lang}: {exc}\n')


if __name__ == '__main__':
    main()
