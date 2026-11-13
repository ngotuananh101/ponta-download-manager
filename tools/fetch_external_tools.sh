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
#
# Downloads. GitHub throttles and stalls anonymous downloads from CI
# runners (a stalled transfer looks like 0% forever, then the job is
# cancelled), so every github.com asset is fetched through a public
# GitHub mirror first and from GitHub itself only as a last resort.
# Mirrors only rewrite github.com URLs. Because a mirror is an
# untrusted third party, every asset is checked against a digest that
# the script pins or that is published next to the asset; a mismatch
# moves on to the next candidate instead of shipping the file.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN_DIR="$ROOT/apps/desktop/bundle/bin"

# Public GitHub mirrors, tried in order for github.com URLs. Both were
# verified to serve byte-identical assets under 10s for a 41 MB file.
GITHUB_MIRRORS=(
  "https://ghfast.top/"
  "https://gh-proxy.com/"
)

# Pinned ffmpeg builds, republished as GitHub release assets by
# https://github.com/eugeneware/ffmpeg-static: the johnvansickle Linux
# static build and gyan.dev's Windows essentials build. The original
# hosts are not reliable from CI (johnvansickle.com stalls outright),
# and a pinned tag keeps the build reproducible. The digests are the
# ones GitHub publishes for each asset; bump the URL and the digest
# together.
FFMPEG_TAG="b6.1.1"
FFMPEG_RELEASE="https://github.com/eugeneware/ffmpeg-static/releases/download/$FFMPEG_TAG"
FFMPEG_LINUX_URL="$FFMPEG_RELEASE/ffmpeg-linux-x64.gz"
FFMPEG_LINUX_SHA256="bfe8a8fc511530457b528c48d77b5737527b504a3797a9bc4866aeca69c2dffa"
FFMPEG_WINDOWS_URL="$FFMPEG_RELEASE/ffmpeg-win32-x64.gz"
FFMPEG_WINDOWS_SHA256="8883a3dffbd0a16cf4ef95206ea05283f78908dbfb118f73c83f4951dcc06d77"

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
need gzip

sha256_of() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | cut -d' ' -f1
  else
    shasum -a 256 "$1" | cut -d' ' -f1
  fi
}

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

# download <url> <out> [expected-sha256] [direct-first]
#
# Tries, in order: the GitHub mirrors (for github.com URLs) or the URL
# itself, then the remaining candidates. A candidate only wins when
# the bytes match the expected digest, so a mirror that truncates,
# rewrites or stalls the transfer is skipped rather than installed.
# --speed-limit/--speed-time turn a stalled transfer (the CI failure
# mode: connected, 0 bytes, forever) into a fast failure.
download() {
  local url="$1" out="$2" want="${3:-}" direct_first="${4:-0}"
  local -a candidates=() mirrors=()

  if [ "$direct_first" -eq 1 ]; then
    candidates+=("$url")
  fi
  case "$url" in
    https://github.com/*)
      local mirror
      for mirror in "${GITHUB_MIRRORS[@]}"; do
        mirrors+=("$mirror$url")
      done
      ;;
  esac
  if [ ${#mirrors[@]} -gt 0 ]; then
    candidates+=("${mirrors[@]}")
  fi
  if [ "$direct_first" -eq 0 ]; then
    candidates+=("$url")
  fi

  local candidate
  for candidate in "${candidates[@]}"; do
    echo "Downloading $candidate"
    rm -f "$out"
    if ! curl -fL --retry 2 --retry-delay 2 \
        --connect-timeout 20 --max-time 1800 \
        --speed-limit 10240 --speed-time 60 \
        -o "$out" "$candidate"; then
      echo "  download failed, trying the next mirror" >&2
      continue
    fi
    if [ -n "$want" ]; then
      local got
      got="$(sha256_of "$out")"
      if [ "$got" != "$want" ]; then
        echo "  checksum mismatch (expected $want, got $got)" >&2
        continue
      fi
    fi
    return 0
  done

  rm -f "$out"
  echo "Could not download $url from any mirror" >&2
  return 1
}

# Prints the sha256 a release publishes for one of its assets. The
# checksum files are tiny, so they are fetched from GitHub directly
# first -- a mirror must not be the only source for the digest the
# mirror's own download is checked against. A missing checksum is
# fatal: an unverified download is not worth installing.
#
# fetch_checksum <checksum-url> <asset-name>
#   The file is in sha256sum format: "<sha256>  <asset-name>".
fetch_checksum() {
  local url="$1" asset="$2" tmp hash=""
  tmp="$(mktemp)"
  # Its stdout is captured by the caller, so the progress lines must
  # not leak into the digest.
  if ! download "$url" "$tmp" "" 1 >&2; then
    rm -f "$tmp"
    echo "Could not fetch $url" >&2
    exit 1
  fi
  hash="$(tr -d '\r' < "$tmp" |
    awk -v a="$asset" '$2 == a { print $1; exit }')"
  rm -f "$tmp"
  if [ -z "$hash" ]; then
    echo "No checksum for $asset in $url" >&2
    exit 1
  fi
  printf '%s' "$hash"
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

  # --- ffmpeg (johnvansickle static build, pinned GitHub asset) ---
  if [ "$FORCE" -eq 0 ] && linux_usable "$BIN_DIR/ffmpeg" -version; then
    echo "ffmpeg already present, skipping"
  else
    download "$FFMPEG_LINUX_URL" "$tmp/ffmpeg.gz" "$FFMPEG_LINUX_SHA256"
    gzip -dc "$tmp/ffmpeg.gz" > "$tmp/ffmpeg"
    [ -s "$tmp/ffmpeg" ] || {
      echo "empty ffmpeg after decompression" >&2
      exit 1
    }
    cp "$tmp/ffmpeg" "$BIN_DIR/ffmpeg"
    chmod +x "$BIN_DIR/ffmpeg"
    record_version "$BIN_DIR/ffmpeg" -version
    echo "ffmpeg -> $BIN_DIR/ffmpeg"
  fi

  # --- yt-dlp (GitHub release, standalone binary) ---
  if [ "$FORCE" -eq 0 ] && linux_usable "$BIN_DIR/yt-dlp" --version; then
    echo "yt-dlp already present, skipping"
  else
    local want
    want="$(fetch_checksum \
      "https://github.com/yt-dlp/yt-dlp/releases/latest/download/SHA2-256SUMS" \
      yt-dlp_linux)"
    download \
      "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp_linux" \
      "$BIN_DIR/yt-dlp" "$want"
    chmod +x "$BIN_DIR/yt-dlp"
    record_version "$BIN_DIR/yt-dlp" --version
    echo "yt-dlp -> $BIN_DIR/yt-dlp"
  fi
}

fetch_windows() {
  mkdir -p "$BIN_DIR"
  local tmp
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN

  # --- ffmpeg.exe (gyan.dev essentials build, pinned GitHub asset) ---
  if [ "$FORCE" -eq 0 ] && windows_usable "$BIN_DIR/ffmpeg.exe"; then
    echo "ffmpeg.exe already present, skipping"
  else
    download \
      "$FFMPEG_WINDOWS_URL" "$tmp/ffmpeg.gz" "$FFMPEG_WINDOWS_SHA256"
    gzip -dc "$tmp/ffmpeg.gz" > "$tmp/ffmpeg.exe"
    [ -s "$tmp/ffmpeg.exe" ] || {
      echo "empty ffmpeg.exe after decompression" >&2
      exit 1
    }
    cp "$tmp/ffmpeg.exe" "$BIN_DIR/ffmpeg.exe"
    echo "ffmpeg.exe -> $BIN_DIR/ffmpeg.exe"
  fi

  # --- yt-dlp.exe (GitHub release, standalone binary) ---
  if [ "$FORCE" -eq 0 ] && windows_usable "$BIN_DIR/yt-dlp.exe"; then
    echo "yt-dlp.exe already present, skipping"
  else
    local want
    want="$(fetch_checksum \
      "https://github.com/yt-dlp/yt-dlp/releases/latest/download/SHA2-256SUMS" \
      yt-dlp.exe)"
    download \
      "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp.exe" \
      "$BIN_DIR/yt-dlp.exe" "$want"
    echo "yt-dlp.exe -> $BIN_DIR/yt-dlp.exe"
  fi
}

if [ "$WANT_LINUX" -eq 1 ]; then
  fetch_linux
fi
if [ "$WANT_WINDOWS" -eq 1 ]; then
  fetch_windows
fi

echo "Done. Binaries in $BIN_DIR:"
ls -la "$BIN_DIR"
