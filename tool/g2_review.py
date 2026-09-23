#!/usr/bin/env python3
"""Diff synthetic renders of the reduced release against the G2 Paper frames.

  python3 tool/g2_review.py              # every frame the harness knows
  python3 tool/g2_review.py 01 02        # only frames 01 and 02
  python3 tool/g2_review.py 02 --dark    # dark only (--light for light only)

Renders with Helvetica Neue extracted from macOS (never committed; cached in
~/Library/Caches/openband5-g2-fonts) and writes, per frame and mode,
build/g2-review/<mode>/<frame>.png = [Paper | app | onion | diff]. The printed
score is the share of differing pixels below the status bar; lower is closer.
References come from tool/paper_refs.py.
"""
import argparse
import os
import struct
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
FLUTTER = Path.home() / '.local/share/flutter/3.41.6/bin/flutter'
TTC = Path('/System/Library/Fonts/HelveticaNeue.ttc')
FONTS = Path.home() / 'Library/Caches/openband5-g2-fonts'
FACES = {'HelveticaNeue', 'HelveticaNeue-Medium', 'HelveticaNeue-Bold'}


def _postscript_name(data, tables):
    offset, _ = tables[b'name']
    _, count, strings = struct.unpack_from('>HHH', data, offset)
    for i in range(count):
        platform, _, _, name_id, length, at = struct.unpack_from('>HHHHHH', data, offset + 6 + 12 * i)
        if name_id == 6:
            raw = data[offset + strings + at: offset + strings + at + length]
            return raw.decode('utf-16-be' if platform in (0, 3) else 'latin-1')
    return None


def extract_fonts():
    """Split the system TTC into the three single-face TTFs Flutter can load."""
    if all((FONTS / f'{face}.ttf').exists() for face in FACES):
        return
    FONTS.mkdir(parents=True, exist_ok=True)
    data = TTC.read_bytes()
    count = struct.unpack_from('>I', data, 8)[0]
    for font_offset in struct.unpack_from(f'>{count}I', data, 12):
        sfnt, num = struct.unpack_from('>IH', data, font_offset)
        records = [struct.unpack_from('>4sIII', data, font_offset + 12 + 16 * i) for i in range(num)]
        tables = {tag: (off, length) for tag, _, off, length in records}
        name = _postscript_name(data, tables)
        if name not in FACES:
            continue
        header = struct.pack('>IHHHH', sfnt, num, *struct.unpack_from('>HHH', data, font_offset + 6))
        body = b''
        cursor = 12 + 16 * num
        directory = b''
        for tag, checksum, off, length in records:
            directory += struct.pack('>4sIII', tag, checksum, cursor + len(body), length)
            body += data[off:off + length] + b'\0' * (-length % 4)
        (FONTS / f'{name}.ttf').write_bytes(header + directory + body)
    missing = [face for face in FACES if not (FONTS / f'{face}.ttf').exists()]
    if missing:
        raise SystemExit(f'{TTC} lacks {missing}')


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('frames', nargs='*', help='Frame numbers, e.g. 01 02.')
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument('--light', action='store_true')
    mode.add_argument('--dark', action='store_true')
    args = parser.parse_args()
    extract_fonts()
    env = dict(os.environ, G2_FONTS=str(FONTS), G2_FRAMES=','.join(args.frames),
               G2_MODES='light' if args.light else 'dark' if args.dark else 'light,dark')
    result = subprocess.run(
        [str(FLUTTER), 'test', '--no-pub', 'tool/g2_review_test.dart'],
        cwd=ROOT, env=env, text=True, capture_output=True,
    )
    scores = [line.split('G2SCORE ', 1)[1] for line in result.stdout.splitlines() if 'G2SCORE ' in line]
    for line in scores:
        print(line)
    if result.returncode != 0 or not scores:
        print(result.stdout[-4000:], result.stderr[-2000:])
        raise SystemExit(result.returncode or 1)
    print(f'-> {ROOT / "build/g2-review"}')


if __name__ == '__main__':
    main()
