#!/usr/bin/env python3
"""Export the G2 Paper frames as PNG references for tool/g2_diff.py.

Read-only against Paper Desktop: it lists artboards and exports them as PNG
through Paper's local MCP relay (~/.paper/bin/paper mcp). Paper writes each
export to ~/Downloads; the script moves it into the repository at once.
(get_screenshot is not used: it returns JPEG and caps frames at 2000 px.) Paper Desktop must be
running with "OpenBand 5 · Designphase 3" available.

  python3 tool/paper_refs.py            # export every G2 frame, light and dark
  python3 tool/paper_refs.py --only 02  # frames whose number is 02
"""
import argparse
import json
import os
import re
import shutil
import subprocess
import threading
import time
import unicodedata
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'docs/openband5/design/paper-g2'
RELAY = Path(os.environ.get('PAPER_RELAY', Path.home() / '.paper/bin/paper'))
FILE_ID = '01M2TRX5GZKAXKTSXK7D34E8AY'
PAGES = {'light': 'p-11-0', 'dark': 'p-12-0'}
SCALE = 2


class Relay:
    def __init__(self):
        self.proc = subprocess.Popen(
            [str(RELAY), 'mcp'], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL, text=True, bufsize=1,
        )
        self.next_id = 0
        self.request('initialize', {
            'protocolVersion': '2025-06-18', 'capabilities': {},
            'clientInfo': {'name': 'openband-paper-refs', 'version': '1'},
        })
        self.send({'jsonrpc': '2.0', 'method': 'notifications/initialized'})

    def send(self, message):
        self.proc.stdin.write(json.dumps(message) + '\n')
        self.proc.stdin.flush()

    def request(self, method, params, timeout=120):
        self.next_id += 1
        rid = self.next_id
        self.send({'jsonrpc': '2.0', 'id': rid, 'method': method, 'params': params})
        result = {}

        def read():
            for line in self.proc.stdout:
                try:
                    message = json.loads(line)
                except json.JSONDecodeError:
                    continue
                if message.get('id') == rid:
                    result['m'] = message
                    return

        reader = threading.Thread(target=read, daemon=True)
        reader.start()
        reader.join(timeout)
        if 'm' not in result:
            raise SystemExit(f'Paper relay timed out on {method}')
        if 'error' in result['m']:
            raise SystemExit(f'Paper relay error on {method}: {result["m"]["error"]}')
        return result['m']['result']

    def tool(self, name, arguments):
        result = self.request('tools/call', {'name': name, 'arguments': arguments})
        if result.get('isError'):
            raise SystemExit(f'{name} failed: {_text(result)[:400]}')
        return result

    def close(self):
        self.proc.stdin.close()
        try:
            self.proc.wait(5)
        except subprocess.TimeoutExpired:
            self.proc.terminate()


def _text(result):
    return '\n'.join(c.get('text', '') for c in result.get('content', []) if c.get('type') == 'text')


def _page(relay, page_id):
    text = _text(relay.tool('get_basic_info', {'fileId': FILE_ID, 'pageId': page_id}))
    return json.loads(text[text.index('{\n  "fileName"'):])


def slug(name):
    # "G2 · 01 · Heute" -> "01-heute"; "G2 · 11 · Dein Datenstand (Sheet)" -> "11-dein-datenstand-sheet"
    rest = re.sub(r'^G2\s*·\s*', '', name)
    ascii_ = unicodedata.normalize('NFKD', rest.replace('ß', 'ss')).encode('ascii', 'ignore').decode()
    return re.sub(r'[^a-z0-9]+', '-', ascii_.lower()).strip('-')


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--only', help='Comma-separated frame numbers, e.g. 01,02.')
    args = parser.parse_args()
    only = set(args.only.split(',')) if args.only else None
    if not RELAY.exists():
        raise SystemExit(f'Paper relay not found at {RELAY}; open Paper Desktop first.')

    relay = Relay()
    manifest_path = OUT / 'manifest.json'
    manifest = json.loads(manifest_path.read_text()) if manifest_path.exists() else {}
    manifest.update({'file': FILE_ID, 'scale': SCALE})
    frames = manifest.setdefault('frames', {})
    failed = 0
    try:
        for mode, page_id in PAGES.items():
            page = _page(relay, page_id)
            (OUT / mode).mkdir(parents=True, exist_ok=True)
            for board in page['artboards']:
                name = slug(board['name'])
                if not name[:2].isdigit():
                    continue  # legend boards, not screens
                if only and name.split('-')[0] not in only:
                    continue
                result = relay.tool('export', {
                    'fileId': FILE_ID, 'pageId': page_id,
                    'nodes': {board['id']: [{'format': 'png', 'scale': f'{SCALE}x'}]},
                })
                exported = [e['filePath'] for t in (_text(result),) for e in json.loads(
                    t[t.index('{\n  "exports"'):])['exports']]
                if len(exported) != 1 or not exported[0].endswith('.png'):
                    print(f'{mode:5} {name}: Paper exported {exported}; kept the previous file')
                    failed += 1
                    continue
                shutil.move(exported[0], OUT / mode / f'{name}.png')
                frames[f'{mode}/{name}'] = {'page': page['pageName'], 'node': board['id'], 'name': board['name']}
                print(f'{mode:5} {name}')
    finally:
        relay.close()
    manifest['exported'] = time.strftime('%Y-%m-%d')
    manifest['frames'] = dict(sorted(frames.items()))
    manifest_path.write_text(json.dumps(manifest, indent=2, ensure_ascii=False) + '\n')
    if failed:
        raise SystemExit(f'{failed} frame(s) not exported')


if __name__ == '__main__':
    main()
