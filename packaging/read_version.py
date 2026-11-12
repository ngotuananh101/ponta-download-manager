#!/usr/bin/env python3
"""Read the app version from apps/desktop/pubspec.yaml.

Prints GitHub Actions output lines (also usable by hand):
    version=0.1.0
    build=1
    msi_version=0.1.0.1

`version` is the `x.y.z` part, `build` the `+N` part, `msi_version`
is the 4-part form WiX needs (<version>.<build>).
"""

import re
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
PUBSPEC = REPO_ROOT / "apps/desktop/pubspec.yaml"
VERSION_RE = re.compile(r"^version:\s*(\d+\.\d+\.\d+)\+(\d+)\s*$", re.M)


def read_version(pubspec=PUBSPEC):
    text = pubspec.read_text(encoding="utf-8")
    match = VERSION_RE.search(text)
    if match is None:
        raise SystemExit(f"error: no 'version: x.y.z+N' line in {pubspec}")
    return match.group(1), match.group(2)


def main(argv=None):
    version, build = read_version()
    print(f"version={version}")
    print(f"build={build}")
    print(f"msi_version={version}.{build}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
