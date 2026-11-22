#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
QT_BIN="${OFFICE_QT_BIN:-$ROOT/.work/Qt/6.11.2/macos/bin}"
mkdir -p "$ROOT/build/office-tests/preferences"
clang++ -std=c++17 -Wall -Wextra -Werror "$ROOT/office/tests/recovery_test.cpp" -o "$ROOT/build/office-tests/recovery"
"$ROOT/build/office-tests/recovery"
clang++ -std=c++17 -Wall -Wextra -Werror -I "$ROOT/app" "$ROOT/office/tests/cursorretry_test.cpp" -o "$ROOT/build/office-tests/cursorretry"
"$ROOT/build/office-tests/cursorretry"
clang++ -std=c++17 -Wall -Wextra -Werror -I "$ROOT/app" "$ROOT/office/tests/scrollspeed_test.cpp" -o "$ROOT/build/office-tests/scrollspeed"
"$ROOT/build/office-tests/scrollspeed"
clang++ -std=c++17 -Wall -Wextra -Werror -I "$ROOT/app" "$ROOT/office/tests/parkedwindow_test.cpp" -o "$ROOT/build/office-tests/parkedwindow"
"$ROOT/build/office-tests/parkedwindow"
clang++ -std=c++17 -Wall -Wextra -Werror -I "$ROOT/app" -I "$ROOT/moonlight-common-c/moonlight-common-c/src" "$ROOT/office/tests/videostats_test.cpp" "$ROOT/app/office/videostats.cpp" -o "$ROOT/build/office-tests/videostats"
"$ROOT/build/office-tests/videostats"
QT_QPA_PLATFORM=offscreen "$QT_BIN/qmltestrunner" -input "$ROOT/tests/office"
cd "$ROOT/build/office-tests/preferences"
"$QT_BIN/qmake" "$ROOT/tests/office/preferences/preferences.pro" QMAKE_APPLE_DEVICE_ARCHS=arm64
make -j4
./office-preferences-test
mkdir -p "$ROOT/build/office-tests/sessions"
cd "$ROOT/build/office-tests/sessions"
"$QT_BIN/qmake" "$ROOT/tests/office/sessions/sessions.pro" QMAKE_APPLE_DEVICE_ARCHS=arm64
make -j4
./office-sessions-test
# Native toolbar checks compile the production SDL/AppKit adapter. A clean CI
# checkout has no libs/mac yet, so prepare the same pinned upstream dependencies
# used by build.sh before compiling the hidden native check.
if [[ ! -d "$ROOT/libs/mac" ]]; then
  (cd "$ROOT" && python3 setup-deps.py)
fi
mkdir -p "$ROOT/build/office-tests/toolbar" "$ROOT/build/office-tests/displayscale"
cd "$ROOT/build/office-tests/toolbar"
"$QT_BIN/qmake" "$ROOT/tests/office/toolbar/check.pro" QMAKE_APPLE_DEVICE_ARCHS=arm64
make -j4
./OfficeToolbarHiddenCheck
cd "$ROOT/build/office-tests/displayscale"
"$QT_BIN/qmake" "$ROOT/tests/office/displayscale/displayscale.pro" QMAKE_APPLE_DEVICE_ARCHS=arm64
make -j4
./office-displayscale-test
mkdir -p "$ROOT/build/office-tests/devicename"
cd "$ROOT/build/office-tests/devicename"
"$QT_BIN/qmake" "$ROOT/tests/office/devicename/devicename.pro" QMAKE_APPLE_DEVICE_ARCHS=arm64
make -j4
./office-devicename-test
mkdir -p "$ROOT/build/office-tests/connectconfirm"
cd "$ROOT/build/office-tests/connectconfirm"
"$QT_BIN/qmake" "$ROOT/tests/office/connectconfirm/connectconfirm.pro" QMAKE_APPLE_DEVICE_ARCHS=arm64
make -j4
./office-connectconfirm-test
mkdir -p "$ROOT/build/office-tests/clipboard"
cd "$ROOT/build/office-tests/clipboard"
"$QT_BIN/qmake" "$ROOT/tests/office/clipboard/clipboard.pro" QMAKE_APPLE_DEVICE_ARCHS=arm64
make -j4
./office-clipboard-test
