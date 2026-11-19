#!/usr/bin/env python3
"""Load the packaged QML in isolation; never use a user's host/identity settings."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time

root = Path(__file__).resolve().parents[2]
bundle = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else root / 'dist/MoonlightDesk.app'
qt_bin = Path(os.environ.get('OFFICE_QT_BIN', root / '.work/Qt/6.11.2/macos/bin'))
(root / '.work').mkdir(exist_ok=True)
stage = Path(tempfile.mkdtemp(prefix='desk-smoke-', dir=root / '.work'))
(stage / 'portable.dat').touch()
settings = stage / 'Moonlight Office/MoonlightOffice.ini'
settings.parent.mkdir()
settings.write_text('[General]\nmdns=false\nuidisplaymode=0\ndefaultver=2\n')
env = os.environ.copy()
env.pop('MOONLIGHT_DESK_SESSION', None)
env.update(QT_QPA_PLATFORM='offscreen', QT_QUICK_BACKEND='software',
           SDL_VIDEODRIVER='dummy', SDL_AUDIODRIVER='dummy',
           QT_QPA_PLATFORM_PLUGIN_PATH=str(qt_bin.parent / 'plugins/platforms'))
with (stage / 'launch.txt').open('w') as log:
    process = subprocess.Popen([str(bundle / 'Contents/MacOS/MoonlightDesk')],
                               cwd=stage, env=env, stdout=log, stderr=log)
    time.sleep(5)
    alive = process.poll() is None
    started_quit = time.monotonic()
    if alive:
        process.terminate()
    forced = False
    try:
        code = process.wait(timeout=45)
    except subprocess.TimeoutExpired:
        forced = True
        process.kill()  # Only this isolated test process; never another app.
        code = process.wait()
logs = '\n'.join(path.read_text(errors='replace') for path in stage.glob('*.log'))
needles = ('ReferenceError', 'TypeError', 'Unable to assign', 'failed to load component',
           'QQmlApplicationEngine failed', 'Binding loop', 'is not a type', 'Qt Fatal', 'Assertion')
errors = [line[:350] for line in logs.splitlines() if any(token in line for token in needles)]
result = dict(isolated_portable=True, mdns=False, platform='offscreen SDK plugin / SDL dummy',
              alive_after_5s=alive, exit_code=code, forced=forced,
              quit_seconds=round(time.monotonic() - started_quit, 2), qml_errors=errors)
(stage / 'result.json').write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n')
print(json.dumps(result, ensure_ascii=False))
print('Evidence:', stage)
sys.exit(0 if alive and code == 0 and not errors and not forced else 1)
