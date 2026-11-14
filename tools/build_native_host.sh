#!/usr/bin/env bash
# Compiles the browser extension's native messaging host into the desktop
# app's bundle directory, so a release build ships it next to ffmpeg and
# yt-dlp (<bundle>/bin/pdm-native-host). The app registers the host with
# every browser it finds at startup; without the binary in the bundle that
# registration is skipped (the manifest must never point at nothing).
#
# Usage:
#   tools/build_native_host.sh            # host platform
#   tools/build_native_host.sh linux|windows
#
# The output is <repo>/apps/desktop/bundle/bin/pdm-native-host[.exe], which
# CMake installs into the bundle (see apps/desktop/*/CMakeLists.txt).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOST_DIR="$ROOT/integrations/browser-extension/host"
OUT_DIR="$ROOT/apps/desktop/bundle/bin"

TARGET="${1:-}"
if [ -z "$TARGET" ]; then
  case "$(uname -s)" in
  MINGW* | MSYS* | CYGWIN*) TARGET=windows ;;
  *) TARGET=linux ;;
  esac
fi

case "$TARGET" in
linux) NAME="pdm-native-host" ;;
windows) NAME="pdm-native-host.exe" ;;
*)
  echo "unknown target: $TARGET (expected linux or windows)" >&2
  exit 2
  ;;
esac

mkdir -p "$OUT_DIR"

echo "Compiling the native host for $TARGET..."
dart compile exe "$HOST_DIR/bin/native_host.dart" -o "$OUT_DIR/$NAME"

if [ ! -x "$OUT_DIR/$NAME" ] && [ ! -f "$OUT_DIR/$NAME" ]; then
  echo "expected $OUT_DIR/$NAME to be produced" >&2
  exit 1
fi
echo "Wrote $OUT_DIR/$NAME"
