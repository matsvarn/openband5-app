#!/usr/bin/env python3
"""Diff Flutter renders of the G3 Bausteine (and registered G3 screens) against Paper.

  python3 tool/g3_review.py refs               # export every registered Paper node
  python3 tool/g3_review.py refs OBLeadMetric  # only names containing the filter
  python3 tool/g3_review.py                    # diff every registered frame, light and dark
  python3 tool/g3_review.py OBChip --dark      # names containing "OBChip", dark only

The registry is docs/openband5/design/paper-g3/frames.json:

  components  Bausteine · G3 nodes, {"light": id, "dark": id, "background": "page"|"canvas"}.
  screens     G3 screen artboards by Paper id, {"page": pageId, "node": id, "mode": "light"|"dark"}.

A later worker registers a screen by adding it to "screens" and a builder of
the same name to `g3ScreenBuilders` in tool/g3_review_test.dart, then runs
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
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tool'))
import g2_review  # noqa: E402  (font extraction, Flutter path)
import paper_refs  # noqa: E402  (Paper relay)

REG = ROOT / 'docs/openband5/design/paper-g3/frames.json'
OUT = ROOT / 'docs/openband5/design/paper-g3'


def registry():
    return json.loads(REG.read_text())


def frames(reg, filt):
    """(name, mode, pageId, nodeId) for every registered frame."""
    out = []
    for name, entry in reg.get('components', {}).items():
        for mode in ('light', 'dark'):
            if entry.get(mode):
                out.append((name, mode, reg['componentsPage'], entry[mode]))
    for name, entry in reg.get('screens', {}).items():
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
    args = parser.parse_args()
    if args.names[:1] == ['refs']:
        export_refs(args.names[1:])
        return
    g2_review.extract_fonts()
    env = dict(os.environ, G2_FONTS=str(g2_review.FONTS), G3_NAMES=','.join(args.names),
               G3_MODES='light' if args.light else 'dark' if args.dark else 'light,dark')
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
    print(f'-> {ROOT / "build/g3-review"}')


if __name__ == '__main__':
    main()
