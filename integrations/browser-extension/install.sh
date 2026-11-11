#!/usr/bin/env bash
# Installs the PDM native messaging host for Chrome and Firefox (Linux).
# Usage: ./install.sh <chrome-extension-id>
# The Chrome extension id is shown on chrome://extensions after loading
# the unpacked extension (Developer mode -> Load unpacked -> extension/).
set -euo pipefail

CHROME_ID="${1:-}"
HOST_BIN="$HOME/.local/bin/pdm-native-host"
HOST_DIR="$(cd "$(dirname "$0")/host" && pwd)"

echo "Building the native host..."
dart compile exe "$HOST_DIR/bin/native_host.dart" -o "$HOST_BIN"

write_manifest() {
  local dir="$1" allowed="$2"
  mkdir -p "$dir"
  cat > "$dir/com.ponta.pdm.json" <<EOF
{
  "name": "com.ponta.pdm",
  "description": "Ponta Download Manager native messaging host",
  "path": "$HOST_BIN",
  "type": "stdio",
  $allowed
}
EOF
  echo "Wrote $dir/com.ponta.pdm.json"
}

# Chrome (and Chromium-based browsers): needs the extension id.
if [ -n "$CHROME_ID" ]; then
  write_manifest "$HOME/.config/google-chrome/NativeMessagingHosts" "\"allowed_origins\": [\"chrome-extension://$CHROME_ID/\"]"
else
  echo "No Chrome extension id given; skipping Chrome. Run ./install.sh <chrome-extension-id> to register Chrome."
fi

# Firefox: the extension id is fixed in its manifest (pdm@ponta.dev).
write_manifest "$HOME/.mozilla/native-messaging-hosts" "\"allowed_extensions\": [\"pdm@ponta.dev\"]"

echo "Done. The PDM app starts automatically when the extension needs it."
