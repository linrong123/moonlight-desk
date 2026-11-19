#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
QT_BIN="${OFFICE_QT_BIN:-$ROOT/.work/Qt/6.11.2/macos/bin}"
BUILD="$ROOT/build/office-release"
mkdir -p "$BUILD" "$ROOT/dist"
if [[ ! -x "$QT_BIN/qmake" ]]; then
  echo '请先安装 Qt，或设置 OFFICE_QT_BIN 指向 Qt 的 bin 目录。' >&2
  exit 1
fi
if [[ ! -d "$ROOT/libs/mac" ]]; then
  (cd "$ROOT" && python3 setup-deps.py)
fi
cd "$BUILD"
"$QT_BIN/qmake" "$ROOT/moonlight-qt.pro" QMAKE_APPLE_DEVICE_ARCHS=arm64 CONFIG+=release
make -j"${OFFICE_BUILD_JOBS:-6}" release
# Deploy into a fresh copy: rebuilding never modifies the app currently tested.
STAGE="$(mktemp -d "$ROOT/build/package.XXXXXX")"
ditto "$BUILD/app/MoonlightOffice.app" "$STAGE/MoonlightOffice.app"
"$QT_BIN/macdeployqt" "$STAGE/MoonlightOffice.app" -qmldir="$ROOT/app" -appstore-compliant -no-codesign > "$STAGE/deploy.log" 2>&1 || {
  cat "$STAGE/deploy.log"
  exit 1
}
python3 "$ROOT/office/macos/verify_bundle.py" "$STAGE/MoonlightOffice.app" "$STAGE/deploy.log"
codesign --force --deep --sign - "$STAGE/MoonlightOffice.app"
codesign --verify --deep --strict "$STAGE/MoonlightOffice.app"
if [[ -d "$ROOT/dist/MoonlightOffice.app" ]]; then
  mv "$ROOT/dist/MoonlightOffice.app" "$STAGE/PreviousMoonlightOffice.app"
fi
ditto "$STAGE/MoonlightOffice.app" "$ROOT/dist/MoonlightOffice.app"
ditto -c -k --sequesterRsrc --keepParent "$STAGE/MoonlightOffice.app" "$ROOT/dist/MoonlightOffice-macOS-arm64.zip"
(cd "$ROOT/dist" && shasum -a 256 MoonlightOffice-macOS-arm64.zip > SHA256SUMS)
echo "构建完成：$ROOT/dist/MoonlightOffice.app（本地签名，未公证）"
