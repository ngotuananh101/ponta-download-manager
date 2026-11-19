#!/usr/bin/env python3
"""Build a desktop release with Git provenance and a UTC build timestamp.

Usage from any directory: python /path/to/repo/tools/build_desktop.py linux|windows
Flutter and Git must be on PATH. External tools/native host are built separately.
"""
import argparse
import shutil
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("target", choices=("linux", "windows"))
    args = parser.parse_args()
    root = Path(__file__).resolve().parent.parent
    try:
        commit = subprocess.check_output(
            ["git", "rev-parse", "HEAD"], cwd=root, text=True,
            stderr=subprocess.PIPE,
        ).strip()
        status = subprocess.check_output(
            ["git", "status", "--porcelain", "--untracked-files=normal"],
            cwd=root, text=True, stderr=subprocess.PIPE,
        ).strip()
    except (OSError, subprocess.CalledProcessError) as error:
        print(f"Could not capture build metadata: {error}", file=sys.stderr)
        return 1
    if status:
        commit += " (dirty)"
    timestamp = datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")
    flutter = shutil.which("flutter")
    if flutter is None:
        print("Flutter is not on PATH", file=sys.stderr)
        return 1
    print(f"Build commit: {commit}\nBuild time (UTC): {timestamp}", flush=True)
    try:
        return subprocess.run(
            [flutter, "build", args.target, "--release",
             f"--dart-define=PDM_BUILD_COMMIT={commit}",
             f"--dart-define=PDM_BUILD_TIME={timestamp}"],
            cwd=root / "apps" / "desktop",
        ).returncode
    except OSError as error:
        print(f"Could not launch Flutter: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
