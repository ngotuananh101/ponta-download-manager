#!/usr/bin/env bash
# Registers the PDM native messaging host with every browser installed for
# the current user (Linux). The desktop app does the same thing itself on
# every launch (BrowserIntegrationService), so this script is only needed
# when running from a source checkout, or to repair a registration by hand:
#
#   ./install.sh                      # build the host, then register it
#   ./install.sh --host <binary>      # register an existing host binary
#                                     # (the release bundle ships one at
#                                     # <bundle>/bin/pdm-native-host)
#
# The Chrome extension id is pinned by the public key in
# extension/manifest.json ("key"), so it is the same on every machine and is
# not a parameter: a mistyped id registers a host Chrome never calls.
set -euo pipefail

CHROME_ID="hiojpajnfchdajfiegibmklalpgndono"
FIREFOX_ID="pdm@ponta.dev"
HOST_NAME="com.ponta.pdm"
CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"

# Chromium-family browsers, as paths below XDG_CONFIG_HOME. Only the ones
# that already exist are registered: creating ~/.config/microsoft-edge for a
# machine without Edge would make Edge look installed.
CHROMIUM_BROWSERS=(
  "google-chrome"
  "chromium"
  "microsoft-edge"
  "BraveSoftware/Brave-Browser"
  "vivaldi"
  "opera"
)

HOST_BIN=""
while [ $# -gt 0 ]; do
  case "$1" in
  --host)
    shift
    HOST_BIN="${1:-}"
    [ -n "$HOST_BIN" ] || {
      echo "--host needs a path" >&2
      exit 2
    }
    ;;
  -h | --help)
    printf '%s\n' 'Usage: install.sh [--host <executable>]' \
      'Without --host, compile the host from source and register detected Linux browsers.' \
      'The Chrome extension ID is pinned; no ID argument is needed.'
    exit 0
    ;;
  *)
    echo "unknown argument: $1 (use --host <binary>)" >&2
    exit 2
    ;;
  esac
  shift
done

if [ -n "$HOST_BIN" ]; then
  if [ ! -x "$HOST_BIN" ]; then
    echo "native host binary not found or not executable: $HOST_BIN" >&2
    exit 1
  fi
  HOST_BIN="$(cd "$(dirname "$HOST_BIN")" && pwd)/$(basename "$HOST_BIN")"
else
  HOST_BIN="$HOME/.local/bin/pdm-native-host"
  HOST_DIR="$(cd "$(dirname "$0")/host" && pwd)"
  echo "Building the native host..."
  mkdir -p "$HOME/.local/bin"
  dart compile exe "$HOST_DIR/bin/native_host.dart" -o "$HOST_BIN"
fi

# Encode the absolute path as JSON, including quotes and control characters.
# -I avoids importing modules from a caller-controlled current directory.
HOST_PATH_JSON="$(python3 -I -c 'import json, sys; print(json.dumps(sys.argv[1]))' "$HOST_BIN")"

write_manifest() {
  local dir="$1" allowed="$2"
  mkdir -p "$dir"
  cat >"$dir/$HOST_NAME.json" <<EOF
{
  "name": "$HOST_NAME",
  "description": "Ponta Download Manager native messaging host",
  "path": $HOST_PATH_JSON,
  "type": "stdio",
  $allowed
}
EOF
  echo "Wrote $dir/$HOST_NAME.json"
}

registered=0
for relative in "${CHROMIUM_BROWSERS[@]}"; do
  browser_config="$CONFIG_HOME/$relative"
  if [ ! -d "$browser_config" ]; then
    continue
  fi
  write_manifest "$browser_config/NativeMessagingHosts" \
    "\"allowed_origins\": [\"chrome-extension://$CHROME_ID/\"]"
  registered=$((registered + 1))
done

# Firefox keeps its manifests outside XDG_CONFIG_HOME.
if [ -d "$HOME/.mozilla" ]; then
  write_manifest "$HOME/.mozilla/native-messaging-hosts" \
    "\"allowed_extensions\": [\"$FIREFOX_ID\"]"
  registered=$((registered + 1))
fi

if [ "$registered" -eq 0 ]; then
  echo "No supported browser found; start one once and run this again." >&2
  exit 1
fi
echo "Done. The PDM app starts automatically when the extension needs it."
