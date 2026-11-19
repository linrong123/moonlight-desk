#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
QT_BIN="${OFFICE_QT_BIN:-$ROOT/.work/Qt/6.11.2/macos/bin}"
BUILD="$ROOT/build/office-release"
DIST="${OFFICE_OUTPUT_DIR:-$ROOT/dist}"
mkdir -p "$BUILD" "$DIST"
if [[ ! -x "$QT_BIN/qmake" ]]; then
  echo '请先安装 Qt，或设置 OFFICE_QT_BIN 指向 Qt 的 bin 目录。' >&2
  exit 1
fi
if [[ ! -d "$ROOT/libs/mac" ]]; then
  (cd "$ROOT" && python3 setup-deps.py)
fi
cd "$BUILD"
"$QT_BIN/qmake" "$ROOT/moonlight-qt.pro" QMAKE_APPLE_DEVICE_ARCHS=arm64 CONFIG+=release
# qmake's cat(version.txt) is not a make dependency. Refresh subprojects so an
# incremental release cannot retain the previous version in its binary/plist.
make qmake_all
make -j"${OFFICE_BUILD_JOBS:-6}" release
# Deploy into a fresh copy: rebuilding never modifies the app currently tested.
STAGE="$(mktemp -d "$ROOT/build/package.XXXXXX")"
ditto "$BUILD/app/MoonlightDesk.app" "$STAGE/MoonlightDesk.app"
"$QT_BIN/macdeployqt" "$STAGE/MoonlightDesk.app" -qmldir="$ROOT/app" -appstore-compliant -no-codesign > "$STAGE/deploy.log" 2>&1 || {
  cat "$STAGE/deploy.log"
  exit 1
}
python3 "$ROOT/office/macos/verify_bundle.py" "$STAGE/MoonlightDesk.app" "$STAGE/deploy.log"
NOTICES="$STAGE/MoonlightDesk.app/Contents/Resources/OfficeSource"
mkdir -p "$NOTICES"
cp "$ROOT/LICENSE" "$NOTICES/LICENSE"
cp "$ROOT/office/THIRD_PARTY.md" "$NOTICES/THIRD_PARTY.md"
ditto "$ROOT/office/licenses" "$NOTICES/licenses"
python3 - "$ROOT" "$NOTICES" <<'PY'
import json, pathlib, subprocess, sys
root, notices = map(pathlib.Path, sys.argv[1:])
commit = subprocess.check_output(['git', '-C', str(root), 'rev-parse', 'HEAD'], text=True).strip()
data = {
    'project': 'Moonlight Desk',
    'source_commit': commit,
    'source_url': f'https://github.com/linrong123/moonlight-desk/tree/{commit}',
    'checkout': 'git clone --recursive https://github.com/linrong123/moonlight-desk.git',
    'build_instructions': 'office/README.md',
    'upstream_tag': 'v6.2.0',
    'dependencies_tag': 'moonlight-qt-deps/v19',
    'working_tree_modified': bool(subprocess.check_output(['git', '-C', str(root), 'status', '--porcelain'], text=True).strip()),
}
(notices / 'SOURCE.json').write_text(json.dumps(data, ensure_ascii=False, indent=2) + '\n')
PY
codesign --force --deep --sign - "$STAGE/MoonlightDesk.app"
codesign --verify --deep --strict "$STAGE/MoonlightDesk.app"
python3 - "$DIST/MoonlightDesk.app" <<'PY'
import pathlib, subprocess, sys
bundle = pathlib.Path(sys.argv[1]).resolve()
binary = str(bundle / 'Contents/MacOS/MoonlightDesk')
running = subprocess.check_output(['ps', '-axo', 'comm='], text=True).splitlines()
if binary in (line.strip() for line in running):
    raise SystemExit('目标应用仍在运行。请设置 OFFICE_OUTPUT_DIR 使用另一个目录；已准备好的构建包保留在 build/package.*。')
PY
if [[ -d "$DIST/MoonlightDesk.app" ]]; then
  mv "$DIST/MoonlightDesk.app" "$STAGE/PreviousMoonlightDesk.app"
fi
ditto "$STAGE/MoonlightDesk.app" "$DIST/MoonlightDesk.app"
ditto -c -k --sequesterRsrc --keepParent "$STAGE/MoonlightDesk.app" "$DIST/MoonlightDesk-macOS-arm64.zip"
(cd "$DIST" && shasum -a 256 MoonlightDesk-macOS-arm64.zip > SHA256SUMS)
echo "构建完成：$DIST/MoonlightDesk.app（本地签名，未公证）"
