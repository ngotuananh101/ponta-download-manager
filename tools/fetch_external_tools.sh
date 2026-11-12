#!/usr/bin/env bash
# Fetches the external binaries PDM bundles (ffmpeg + yt-dlp) into
# apps/desktop/bundle/bin/. The binaries are NOT committed to git;
# run this once before building, and again after a clean checkout.
#
# Usage:
#   tools/fetch_external_tools.sh [--force] [linux|windows|all]
#     --force   re-download even when a working binary is present
#     linux     fetch Linux x64 binaries (default on Linux hosts)
#     windows   fetch Windows x64 binaries
#     all       fetch both platforms
#
# Idempotency: a binary is skipped when it already exists, is
# executable (Linux), and reports a version. Pass --force to
# re-download. The resolved version is recorded in <name>.version
# next to each binary.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN_DIR="$ROOT/apps/desktop/bundle/bin"

FORCE=0
WANT_LINUX=0
WANT_WINDOWS=0

for arg in "$@"; do
  case "$arg" in
    --force) FORCE=1 ;;
    linux) WANT_LINUX=1 ;;
    windows) WANT_WINDOWS=1 ;;
    all) WANT_LINUX=1; WANT_WINDOWS=1 ;;
    *) echo "Unknown argument: $arg" >&2; exit 1 ;;
  esac
done

if [ "$WANT_LINUX" -eq 0 ] && [ "$WANT_WINDOWS" -eq 0 ]; then
  case "$(uname -s)" in
    Linux) WANT_LINUX=1 ;;
    MINGW*|MSYS*|CYGWIN*) WANT_WINDOWS=1 ;;
    *) echo "Cannot detect host platform: $(uname -s)" >&2; exit 1 ;;
  esac
fi

need() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Missing required tool: $1" >&2
    exit 1
  }
}
need curl
need tar

# True when a Linux binary is present, executable, and reports a
# version with its own flag ($2): ffmpeg takes -version (--version
# exits 8), yt-dlp takes --version. Windows binaries cannot be
# executed on a Linux host, so they only need to exist and be non-empty.
linux_usable() {
  [ -x "$1" ] && [ -s "$1" ] && "$1" "$2" >/dev/null 2>&1
}
windows_usable() {
  [ -s "$1" ]
}

download() {
  local url="$1" out="$2"
  echo "Downloading $url"
  curl -fL --retry 3 -o "$out" "$url"
}

record_version() {
  local bin="$1" flag="$2"
  "$bin" "$flag" 2>&1 | head -n 1 > "$bin.version" || true
}

fetch_linux() {
  mkdir -p "$BIN_DIR"
  local tmp
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN

  # --- ffmpeg (johnvansickle static build) ---
  if [ "$FORCE" -eq 0 ] && linux_usable "$BIN_DIR/ffmpeg" -version; then
    echo "ffmpeg already present, skipping"
  else
    download \
      "https://johnvansickle.com/ffmpeg/releases/ffmpeg-release-amd64-static.tar.xz" \
      "$tmp/ffmpeg.tar.xz"
    tar -xJf "$tmp/ffmpeg.tar.xz" -C "$tmp"
    local found
    found="$(find "$tmp" -type f -name ffmpeg -print -quit)"
    [ -n "$found" ] || { echo "ffmpeg not found in tarball" >&2; exit 1; }
    cp "$found" "$BIN_DIR/ffmpeg"
    chmod +x "$BIN_DIR/ffmpeg"
    record_version "$BIN_DIR/ffmpeg" -version
    echo "ffmpeg -> $BIN_DIR/ffmpeg"
  fi

  # --- yt-dlp (GitHub release, standalone binary) ---
  if [ "$FORCE" -eq 0 ] && linux_usable "$BIN_DIR/yt-dlp" --version; then
    echo "yt-dlp already present, skipping"
  else
    download \
      "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp_linux" \
      "$BIN_DIR/yt-dlp"
    chmod +x "$BIN_DIR/yt-dlp"
    record_version "$BIN_DIR/yt-dlp" --version
    echo "yt-dlp -> $BIN_DIR/yt-dlp"
  fi
}

fetch_windows() {
  need unzip
  mkdir -p "$BIN_DIR"
  local tmp
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN

  # --- ffmpeg.exe (gyan.dev essentials build) ---
  if [ "$FORCE" -eq 0 ] && windows_usable "$BIN_DIR/ffmpeg.exe"; then
    echo "ffmpeg.exe already present, skipping"
  else
    download \
      "https://www.gyan.dev/ffmpeg/builds/ffmpeg-release-essentials.zip" \
      "$tmp/ffmpeg.zip"
    unzip -j -o "$tmp/ffmpeg.zip" '*/bin/ffmpeg.exe' -d "$tmp" >/dev/null
    [ -s "$tmp/ffmpeg.exe" ] || {
      echo "ffmpeg.exe not found in zip" >&2
      exit 1
    }
    cp "$tmp/ffmpeg.exe" "$BIN_DIR/ffmpeg.exe"
    echo "ffmpeg.exe -> $BIN_DIR/ffmpeg.exe"
  fi

  # --- yt-dlp.exe (GitHub release, standalone binary) ---
  if [ "$FORCE" -eq 0 ] && windows_usable "$BIN_DIR/yt-dlp.exe"; then
    echo "yt-dlp.exe already present, skipping"
  else
    download \
      "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp.exe" \
      "$BIN_DIR/yt-dlp.exe"
    echo "yt-dlp.exe -> $BIN_DIR/yt-dlp.exe"
  fi
}

[ "$WANT_LINUX" -eq 1 ] && fetch_linux
[ "$WANT_WINDOWS" -eq 1 ] && fetch_windows

echo "Done. Binaries in $BIN_DIR:"
ls -la "$BIN_DIR"
