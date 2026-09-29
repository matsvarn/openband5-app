#!/usr/bin/env python3
"""Diff Flutter renders of the G3 Bausteine (and registered G3 screens) against Paper.

  python3 tool/g3_review.py refs               # export every registered Paper node
  python3 tool/g3_review.py refs OBLeadMetric  # only names containing the filter
  python3 tool/g3_review.py                    # diff every registered frame, light and dark
  python3 tool/g3_review.py OBChip --dark      # names containing "OBChip", dark only
  python3 tool/g3_review.py --real heute       # render screens from the newest pulled phone DB
  python3 tool/g3_review.py --real PATH --day 2026-09-28

--real renders the registered SCREENS (not components) from a COPY of a database
pulled with tool/pull_device_db.sh (newest by default, or --real PATH to its
Documents folder), for the latest stored day unless --day is given. Real data is
private: the PNGs go to OpenBand5Lab/ui-review-real/<stamp>/, never to the
repository, and nothing is compared with Paper. Screen builders follow the
contract at the top of tool/g3_review_test.dart.

The registry is docs/openband5/design/paper-g3/frames.json:

  components  Bausteine · G3 nodes, {"light": id, "dark": id, "background": "page"|"canvas"}.
  screens     G3 screen artboards by Paper id, {"page": pageId, "node": id, "mode": "light"|"dark"}.

A screen is registered in docs/openband5/design/paper-g3/screens/<area>.json
with a builder of the same name in tool/g3_screens/<area>.dart, then one runs
`refs` and the diff. References land in docs/openband5/design/paper-g3/{light,dark}/
as <name>.png (2x). Reports go to build/g3-review/<mode>/<name>.png as
[Paper | app | onion | diff]; the score is the share of differing pixels
(any channel off by more than 24), lower is closer. Paper node exports are
transparent outside the node; the harness puts them on the registered
background before comparing, and the app renders on the same background.

Fonts: Helvetica Neue is extracted from macOS by tool/g2_review.py (never committed).
"""
import argparse
import json
import os
import shutil
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tool'))
import g2_review  # noqa: E402  (font extraction, Flutter path)
import paper_refs  # noqa: E402  (Paper relay)

REG = ROOT / 'docs/openband5/design/paper-g3/frames.json'
OUT = ROOT / 'docs/openband5/design/paper-g3'


def registry():
    return json.loads(REG.read_text())


def screens(reg):
    """Screens from frames.json plus one file per area in paper-g3/screens/."""
    out = dict(reg.get('screens', {}))
    for path in sorted((REG.parent / 'screens').glob('*.json')):
        out.update(json.loads(path.read_text()))
    return out


def frames(reg, filt):
    """(name, mode, pageId, nodeId) for every registered frame."""
    out = []
    for name, entry in reg.get('components', {}).items():
        for mode in ('light', 'dark'):
            if entry.get(mode):
                out.append((name, mode, reg['componentsPage'], entry[mode]))
    for name, entry in screens(reg).items():
        out.append((name, entry['mode'], entry['page'], entry['node']))
    return [f for f in out if not filt or any(s in f[0] for s in filt)]


def export_refs(filt):
    reg = registry()
    relay = paper_refs.Relay()
    failed = 0
    try:
        for name, mode, page, node in frames(reg, filt):
            for _ in range(3):  # Paper occasionally answers an export with an empty list
                result = relay.tool('export', {
                    'fileId': reg['file'], 'pageId': page,
                    'nodes': {node: [{'format': 'png', 'scale': f"{reg.get('scale', 2)}x"}]},
                })
                text = paper_refs._text(result)
                exported = [e['filePath'] for e in json.loads(text[text.index('{\n  "exports"'):])['exports']]
                if exported:
                    break
            if len(exported) != 1 or not exported[0].endswith('.png'):
                print(f'{mode:5} {name}: Paper exported {exported}; kept the previous file')
                failed += 1
                continue
            (OUT / mode).mkdir(parents=True, exist_ok=True)
            shutil.move(exported[0], OUT / mode / f'{name}.png')
            print(f'{mode:5} {name} <- {node}')
    finally:
        relay.close()
    if failed:
        raise SystemExit(f'{failed} frame(s) not exported')


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('names', nargs='*', help='"refs" to export references, then optional name filters.')
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument('--light', action='store_true')
    mode.add_argument('--dark', action='store_true')
    parser.add_argument('--real', nargs='?', const='newest', metavar='DOCUMENTS',
                        help='Render screens from a pulled phone DB (newest pull, or this Documents folder).')
    parser.add_argument('--day', help='With --real: the day to render (YYYY-MM-DD).')
    args = parser.parse_args()
    if args.real and args.real != 'newest' and not Path(args.real).expanduser().exists():
        # `--real heute`: the first name is a filter, not a folder.
        args.names.insert(0, args.real)
        args.real = 'newest'
    if args.names[:1] == ['refs']:
        export_refs(args.names[1:])
        return
    g2_review.extract_fonts()
    env = dict(os.environ, G2_FONTS=str(g2_review.FONTS), G3_NAMES=','.join(args.names),
               G3_MODES='light' if args.light else 'dark' if args.dark else 'light,dark')
    out = ROOT / 'build/g3-review'
    if args.real:
        docs = g2_review.newest_pull() if args.real == 'newest' else Path(args.real).expanduser()
        if not (docs / 'openstrap.db').exists():
            raise SystemExit(f'No openstrap.db in {docs}')
        out = g2_review.LAB / 'ui-review-real' / time.strftime('%Y%m%d-%H%M%S')
        env.update(G3_REAL_DOCS=str(docs), G3_OUT=str(out))
        if args.day:
            env['G3_REAL_DAY'] = args.day
        print(f'real data: {docs}')
    result = subprocess.run(
        [str(g2_review.FLUTTER), 'test', '--no-pub', 'tool/g3_review_test.dart'],
        cwd=ROOT, env=env, text=True, capture_output=True,
    )
    scores = [line.split('G3SCORE ', 1)[1] for line in result.stdout.splitlines() if 'G3SCORE ' in line]
    for line in scores:
        print(line)
    if result.returncode != 0 or not scores:
        print(result.stdout[-4000:], result.stderr[-2000:])
        raise SystemExit(result.returncode or 1)
    print(f'-> {out}')


if __name__ == '__main__':
    main()
