#!/usr/bin/env python3
"""Run OpenBand's synthetic native UI review without Device Hub."""
import argparse
import datetime
import json
import os
import http.server
import re
import threading
from pathlib import Path
import subprocess
import time

ROOT = Path(__file__).resolve().parents[1]
SDK = Path.home() / '.local/share/flutter/3.41.6/bin/flutter'


def run(*args, capture=False, **kwargs):
    return subprocess.run(
        [str(a) for a in args], cwd=ROOT, check=True, text=True,
        stdout=subprocess.PIPE if capture else None, **kwargs,
    )


def simulator(small):
    name = 'OpenBand Review - ' + ('iPhone 13 mini' if small else 'iPhone 15 Pro')
    devices = json.loads(run('xcrun', 'simctl', 'list', 'devices', 'available', '--json', capture=True).stdout)
    matches = [d for ds in devices['devices'].values() for d in ds if d['name'] == name]
    if len(matches) > 1:
        raise SystemExit(f'Multiple review simulators named {name}; resolve the duplicate names first.')
    if matches:
        device = matches[0]
        udid = device['udid']
    else:
        kind = 'iPhone-13-mini' if small else 'iPhone-15-Pro'
        udid = run('xcrun', 'simctl', 'create', name,
                   f'com.apple.CoreSimulator.SimDeviceType.{kind}',
                   'com.apple.CoreSimulator.SimRuntime.iOS-26-5', capture=True).stdout.strip()
        device = {'state': 'Shutdown'}
    if device['state'] != 'Booted':
        run('xcrun', 'simctl', 'boot', udid)
    run('xcrun', 'simctl', 'bootstatus', udid, '-b')
    return name, udid



def capture_server(device, output):
    class Handler(http.server.BaseHTTPRequestHandler):
        def do_GET(self):
            match = re.fullmatch(r'/capture/([a-z0-9-]{1,80})', self.path)
            if not match:
                self.send_error(400)
                return
            try:
                run('xcrun', 'simctl', 'io', device, 'screenshot',
                    output / (match.group(1) + '.png'), timeout=25)
            except (subprocess.SubprocessError, OSError):
                self.send_error(500, 'Native capture failed')
                return
            self.send_response(200)
            self.end_headers()

        def log_message(self, *args):
            pass

    server = http.server.HTTPServer(('127.0.0.1', 0), Handler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    return server


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('mode', choices=['gallery', 'capture'])
    parser.add_argument('--small', action='store_true', help='Use a dedicated 375×812 iPhone 13 mini instead of 393×852 iPhone 15 Pro.')
    parser.add_argument('--output', type=Path, help='Native review output directory; defaults to build/ui-review/<timestamp>.')
    parser.add_argument('--flow', choices=['all', 'journal', 'journal-hub', 'nutrition-entry', 'nutrition-parent', 'sleep-plan', 'exercise-picker', 'custom-exercise', 'custom-load', 'glucose', 'medications', 'cycle'], default='all',
                        help='Native capture flow: full gallery (default), Journal, Journal hub, saved food entry, nutrition parent, sleep plan, exercise picker, custom exercise, custom load, glucose, medications, or cycle.')
    args = parser.parse_args()
    if not SDK.is_file():
        raise SystemExit(f'Pinned Flutter SDK not found: {SDK}')
    name, device = simulator(args.small)
    print(f'{name}: {device}', flush=True)
    if args.mode == 'gallery':
        run(SDK, 'run', '--no-pub', '-d', device, '-t', 'lib/main_gallery.dart')
        return
    output = (args.output or ROOT / 'build/ui-review' / datetime.datetime.now().strftime('%Y%m%d-%H%M%S')).resolve()
    output.mkdir(parents=True, exist_ok=True)
    if any(output.iterdir()):
        raise SystemExit('Choose an empty output directory to keep review runs separate.')
    started = time.monotonic()
    manifest = {'synthetic': True, 'device': name, 'udid': device,
                'sdk': str(SDK), 'runtime': 'iOS 26.5', 'captureKind': 'simulator-display',
                'flow': args.flow, 'success': False}
    run('xcrun', 'simctl', 'status_bar', device, 'override', '--time', '09:41',
        '--batteryState', 'charged', '--batteryLevel', '100')
    env = {**os.environ, 'OPENBAND_REVIEW_OUTPUT': str(output)}
    server = capture_server(device, output)
    try:
        run(SDK, 'drive', '--no-pub', '-d', device,
            '--driver=test_driver/openband_review.dart',
            '--target=integration_test/openband_review_test.dart',
            f'--dart-define=OPENBAND_REVIEW_PORT={server.server_port}',
            f'--dart-define=OPENBAND_REVIEW_FLOW={args.flow}', env=env)
        manifest['success'] = True
    finally:
        server.shutdown()
        server.server_close()
        manifest['elapsedSeconds'] = round(time.monotonic() - started, 2)
        (output / 'run.json').write_text(json.dumps(manifest, indent=2) + '\n')
        screenshots = sorted(output.glob('*.png'))
        (output / 'index.html').write_text(
            '<!doctype html><meta charset="utf-8"><title>OpenBand synthetic native review</title>'
            '<style>body{font:16px system-ui;background:#eef0f4;margin:24px}main{display:flex;flex-wrap:wrap;gap:24px}'
            'figure{margin:0}img{width:295px;border:1px solid #ddd}figcaption{padding:8px 0;max-width:295px}</style>'
            '<h1>OpenBand · synthetic native review</h1><p>Native simulator renders; no real user data. '
            f'Run passed: {manifest["success"]}. Duration: {manifest["elapsedSeconds"]} s. '
            f'Flow: {manifest["flow"]}.</p><main>'
            + ''.join(f'<figure><img src="{p.name}"><figcaption>{p.stem}</figcaption></figure>' for p in screenshots)
            + '</main>'
        )
        print(f'Review: {output / "index.html"}', flush=True)


if __name__ == '__main__':
    main()
