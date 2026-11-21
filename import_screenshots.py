# =============================================================================
# APMon - EdgeTX Monitor for ArduPilot
# File: import_screenshots.py
# Purpose: Import and label EdgeTX SD-card screenshots without altering the radio.
# Project version: 0.4.0
# Updated: 2026-11-20
# Authors: Christian Baun
# Development assistance: OpenAI Codex CLI (code, tests and documentation)
# SPDX-License-Identifier: Apache-2.0
# License: Apache License, Version 2.0 (https://www.apache.org/licenses/LICENSE-2.0)
# See LICENSE in the repository.
# =============================================================================

# Screenshot-Import: Ablauf und Voraussetzungen
# ----------------------------------------------
# 1. Auf dem Sender mit der EdgeTX-Spezialfunktion «Screenshot» Aufnahmen
#    machen und den Sender anschließend im USB-Speichermodus anschließen.
#    Eine separat eingehängte Sender-SD-Karte funktioniert ebenfalls.
# 2. Das Skript liest BMP- und PNG-Dateien direkt aus SCREENSHOTS. Mit --list
#    lassen sich die Originalnamen und die jeweiligen Zeitstempel prüfen.
# 3. Ohne --file werden alle neuen Aufnahmen zur Übernahme vorgeschlagen.
#    Bereits importierte Aufnahmen erkennt das Skript innerhalb desselben
#    Displaytyps an Aufnahmezeit und Bildinhalt, auch wenn Ansicht, Sprache,
#    Version oder Vergrößerung beim früheren Import anders angegeben wurden.
# 4. Ohne --apply werden nur die vorgesehenen Zieldateien angezeigt. Mit
#    --apply wird in images/screenshots/ relativ zum Repository geschrieben.
#    Die Originale auf der SD-Karte werden weder verändert noch gelöscht.
#
# Vorschau und Import brauchen Pillow ab 9.1 (unter Debian: python3-pil).
# --help und --list funktionieren ohne Pillow.
#
# Parameter
# ---------
# --help, -h       Zeigt die Kurzreferenz der Kommandozeile.
# --sd PFAD        Stammverzeichnis der eingehängten SD-Karte, nicht
#                  SCREENSHOTS selbst. Es muss MODELS, RADIO und SCRIPTS
#                  enthalten. Ohne --sd sucht das Skript wie deploy.py unter
#                  /run/media, /media und /mnt nach genau einer Karte.
# --list           Zeigt alle gefundenen Aufnahmen, neueste zuerst, ohne
#                  Import. Nicht mit --file oder --apply kombinieren.
# --display        Pflicht beim Import: sw für 128 × 64 Pixel (GX12, Boxer)
#                  oder color ab 440 × 252 Pixel (z. B. GX15: 480 × 320).
#                  Die Originalabmessungen werden vor dem Import geprüft.
# --view           Pflicht: overview (Übersicht), flight (Flugwerte),
#                  menu (Projektmenü), language (Sprachwahl), messages
#                  (FC-Meldungen) oder diagnostics (APDiag).
# --lang, --language
#                  Pflicht: de oder en, entsprechend der angezeigten Sprache.
#                  Ansicht und Sprache werden nicht aus dem Bild erkannt.
#                  Die Angaben gelten für alle Dateien dieses Durchlaufs.
# --radio MODELL   Optionaler Namenszusatz, z. B. gx12, boxer oder gx15.
#                  Erlaubt sind Buchstaben, Ziffern und einzelne Bindestriche.
# --file NAME      Optional: exakter Originaldateiname aus --list, ohne Pfad.
#                  Für mehrere Dateien mit gleichen Metadaten wiederholen.
#                  Eine explizite Auswahl kann auch dann erneut benannt
#                  werden, wenn der automatische Import sie überspringt.
# --version WERT   Tatsächlich auf dem Sender laufende APMon-Version, z. B.
#                  0.2.1 oder v0.2.2-rc.1. Standard: Inhalt von VERSION.
# --scale FAKTOR   Ganzzahlig von 1 bis 8; Standard 1 (Originalauflösung).
#                  Faktor 4 macht aus 128 × 64 Pixeln ein 512 × 256-PNG.
#                  Nearest Neighbor hält die Pixelkanten scharf.
# --apply          Speichert die PNGs; ohne diese Option nur Vorschau.
#
# Dateinamen und Zeitstempel
# -------------------------
# Muster: apmon-<display>[-<radio>]-<view>-<lang>-v<version>-<datum>-<uhrzeit>[-<faktor>x].png
# Beispiel: apmon-sw-gx12-overview-de-v0.2.1-2026-11-20-090305-4x.png
# Datum und Uhrzeit kommen aus dem EdgeTX-Namen screen-JJJJ-MM-TT-HHMMSS.
# Bei abweichenden Namen gilt die Dateiänderungszeit in der lokalen Zeitzone.
# Eine falsch eingestellte Senderuhr wird nicht automatisch korrigiert.
# Existierende PNGs werden nicht überschrieben. Bei gleichem Namen, aber
# anderem Inhalt, wird ein Suffix wie -02 oder -03 ergänzt.
#
# Beispielaufrufe aus dem Projektverzeichnis
# -----------------------------------------
# Alle vorhandenen Originaldateien anzeigen:
#   python3 import_screenshots.py --list
# Alle neuen GX12-Aufnahmen mit denselben Metadaten in der Vorschau sehen:
#   python3 import_screenshots.py --display sw --radio gx12 --view overview --lang de --scale 4
# Nach Prüfung dieselben Aufnahmen tatsächlich importieren:
#   python3 import_screenshots.py --display sw --radio gx12 --view overview --lang de --scale 4 --apply
# Eine bestimmte englische GX15-Menüaufnahme mit explizitem Kartenpfad importieren:
#   python3 import_screenshots.py --sd /run/media/USER/EDGETX --display color --radio gx15 \
#       --view menu --lang en --file screen-2026-11-20-101532.bmp --version v0.2.1 --apply
# Zwei Boxer-Aufnahmen der Flugseite mit denselben Metadaten importieren:
#   python3 import_screenshots.py --display sw --radio boxer --view flight --lang en \
#       --file screen-2026-11-20-102030.bmp --file screen-2026-11-20-102105.bmp --apply

"""Preview or import EdgeTX screenshots from a mounted SD card as named PNGs."""
import argparse
from datetime import datetime
from io import BytesIO
from pathlib import Path
import re
import sys

from deploy import resolve_card

ROOT = Path(__file__).resolve().parent
VIEWS = ('overview', 'flight', 'menu', 'language', 'messages', 'diagnostics')
STAMP = '%Y-%m-%d-%H%M%S'
VERSION_PATTERN = r'v?[0-9]+\.[0-9]+\.[0-9]+(?:-[A-Za-z0-9]+(?:[.-][A-Za-z0-9]+)*)?'
EXPORT_STAMP = re.compile(r'-(\d{4}-\d{2}-\d{2}-\d{6})(?:-([1-8])x)?(?:-\d{2,})?\.png$')


def capture_time(path):
    try:
        return datetime.strptime(path.stem.lower(), 'screen-' + STAMP), 'EdgeTX filename'
    except ValueError:
        return datetime.fromtimestamp(path.stat().st_mtime), 'file modification time'


def screenshot_files(card):
    folder = card / 'SCREENSHOTS'
    if folder.is_symlink() or not folder.is_dir():
        raise ValueError(f'No SCREENSHOTS folder on {card}; take a screenshot on the radio first.')
    captures = {}
    for path in folder.iterdir():
        if path.suffix.lower() in ('.bmp', '.png') and not path.is_symlink() and path.is_file():
            captures[path.name] = capture_time(path)
    return folder, captures


def load_capture(image_module, path, display):
    with image_module.open(path, formats=('BMP', 'PNG')) as screenshot:
        width, height = screenshot.size
        if display == 'sw' and (width, height) != (128, 64):
            raise ValueError(f'{path.name}: SW expects 128x64, got {width}x{height}.')
        if display == 'color' and (width < 440 or height < 252):
            raise ValueError(f'{path.name}: COLOR expects at least 440x252, got {width}x{height}.')
        image = screenshot.convert('RGB')
    image.info.clear()
    return image


def scaled(image_module, image, scale):
    if scale == 1:
        return image
    return image.resize((image.width * scale, image.height * scale), image_module.Resampling.NEAREST)


def png_bytes(image):
    output = BytesIO()
    image.save(output, format='PNG')
    return output.getvalue()


def index_imports(directory, display):
    """Find existing exports by capture time, regardless of the supplied labels."""
    exports = {}
    for path in sorted(directory.glob(f'apmon-{display}-*.png')):
        match = EXPORT_STAMP.search(path.name)
        if match and not path.is_symlink() and path.is_file():
            stamp, scale = match.groups()
            exports.setdefault(stamp, []).append((path, int(scale or 1)))
    return exports


def existing_capture(image_module, image, candidates):
    pixels = {}
    for path, scale in candidates:
        try:
            with image_module.open(path, formats=('PNG',)) as existing:
                if existing.size != (image.width * scale, image.height * scale):
                    continue
                if scale not in pixels:
                    pixels[scale] = scaled(image_module, image, scale).tobytes()
                if existing.convert('RGB').tobytes() == pixels[scale]:
                    return path
        except OSError:
            # A damaged export is not a successful import; do not overwrite it.
            continue
    return None


def choose_destination(directory, stem, content, pending):
    number = 1
    while True:
        suffix = f'-{number:02d}' if number > 1 else ''
        path = directory / f'{stem}{suffix}.png'
        if path in pending:
            if pending[path] == content:
                return path, False
        elif not path.is_symlink():
            if not path.exists():
                pending[path] = content
                return path, True
            if path.is_file() and path.read_bytes() == content:
                return path, False
        number += 1


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--sd', type=Path, help='Mounted SD-card root (same detection as deploy.py)')
    parser.add_argument('--list', action='store_true', help='List available captures; no image conversion')
    parser.add_argument('--file', action='append', metavar='NAME',
                        help='Original name in SCREENSHOTS; repeat for more files. Defaults to all new captures.')
    parser.add_argument('--display', choices=('sw', 'color'), help='Display type for the import')
    parser.add_argument('--view', choices=VIEWS, help='APMon page shown in the image')
    parser.add_argument('--lang', '--language', choices=('de', 'en'), help='APMon display language')
    parser.add_argument('--radio', type=str.lower, help='Optional model slug, e.g. gx12, boxer or gx15')
    parser.add_argument('--version', help='Version shown on the radio; defaults to repository VERSION')
    parser.add_argument('--scale', type=int, choices=range(1, 9), default=1,
                        help='Integer pixel enlargement, e.g. 4 for SW (default: native size)')
    parser.add_argument('--apply', action='store_true', help='Write PNGs (default: preview)')
    args = parser.parse_args()
    if args.list and (args.apply or args.file):
        parser.error('--list cannot be combined with --apply or --file')
    if not args.list and not (args.display and args.view and args.lang):
        parser.error('Provide --display, --view and --lang, or use --list.')
    if args.radio and not re.fullmatch(r'[a-z0-9]+(?:-[a-z0-9]+)*', args.radio):
        parser.error('--radio must contain only letters, digits or single hyphens.')

    card = resolve_card(parser, args.sd)
    folder, captures = screenshot_files(card)
    ordered = sorted(captures, key=lambda name: (captures[name][0], name), reverse=True)
    print('SD card:', card)
    if args.list:
        for name in ordered:
            timestamp, source = captures[name]
            print(f'{timestamp:%Y-%m-%d %H:%M:%S}  {name}  ({source})')
        if not ordered:
            print('No BMP or PNG screenshots found.')
        return
    if not ordered and not args.file:
        print(f'No BMP or PNG screenshots found in {folder}.')
        return

    names = list(dict.fromkeys(args.file or ordered))
    for name in names:
        if name not in captures:
            parser.error(f'Screenshot not found in SCREENSHOTS: {name!r}. Use --list.')
    version = args.version if args.version is not None else (ROOT / 'VERSION').read_text().strip()
    if not re.fullmatch(VERSION_PATTERN, version):
        parser.error('Expected a version like 0.2.1 or v0.2.2-rc.1.')
    try:
        from PIL import Image
    except ImportError as exc:
        raise ValueError('Pillow 9.1+ is required to preview or import images (e.g. Debian: python3-pil).') from exc

    directory = ROOT / 'images' / 'screenshots'
    if directory.resolve() != directory:
        raise ValueError(f'Refusing redirected screenshot directory: {directory}')
    prefix = ['apmon', args.display]
    if args.radio:
        prefix.append(args.radio)
    prefix.extend((args.view, args.lang, 'v' + version.lstrip('v')))

    pending = {}
    exports = index_imports(directory, args.display) if not args.file else {}
    for name in names:
        timestamp, source = captures[name]
        stamp = timestamp.strftime(STAMP)
        image = load_capture(Image, folder / name, args.display)
        known = existing_capture(Image, image, exports.get(stamp, ()))
        if known is not None:
            print(f'Already imported: {name} -> {known.relative_to(ROOT)}')
            continue
        content = png_bytes(scaled(Image, image, args.scale))
        stem = '-'.join((*prefix, stamp))
        if args.scale > 1:
            stem += f'-{args.scale}x'
        path, is_new = choose_destination(directory, stem, content, pending)
        action = 'Import' if is_new else 'Already present'
        print(f'{action}: {name} -> {path.relative_to(ROOT)} ({source})')
    if not args.apply:
        print('Preview only. Add --apply to write the PNGs.')
        return
    if pending:
        directory.mkdir(parents=True, exist_ok=True)
    for path, content in pending.items():
        with path.open('xb') as output:
            output.write(content)
    print(f'Imported {len(pending)} screenshot(s). SD card unchanged.')


if __name__ == '__main__':
    try:
        main()
    except (OSError, OverflowError, ValueError) as exc:
        sys.exit('Screenshot import failed: ' + str(exc))
