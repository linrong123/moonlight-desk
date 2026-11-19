#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
QT_BIN="${OFFICE_QT_BIN:-$ROOT/.work/Qt/6.11.2/macos/bin}"
mkdir -p "$ROOT/build/office-tests/preferences"
clang++ -std=c++17 -Wall -Wextra -Werror "$ROOT/office/tests/recovery_test.cpp" -o "$ROOT/build/office-tests/recovery"
"$ROOT/build/office-tests/recovery"
QT_QPA_PLATFORM=offscreen "$QT_BIN/qmltestrunner" -input "$ROOT/tests/office"
cd "$ROOT/build/office-tests/preferences"
"$QT_BIN/qmake" "$ROOT/tests/office/preferences/preferences.pro" QMAKE_APPLE_DEVICE_ARCHS=arm64
make -j4
./office-preferences-test
