"""Behavioural tests for the repo's shell scripts (review items 34, 35, 38).

Run: pytest tools/test_shell_scripts.py

Each test copies the real script into a temp layout and runs it with
fake tools on PATH, so no network and no real binaries are involved.
"""
import os
import shutil
import stat
import subprocess
import textwrap
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent


def write_executable(path, content):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(textwrap.dedent(content))
    path.chmod(path.stat().st_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)


def run_script(script, *, cwd, args=(), env_extra=None):
    env = dict(os.environ)
    if env_extra:
        env.update(env_extra)
    return subprocess.run(
        ["bash", str(script), *[str(a) for a in args]],
        cwd=cwd,
        env=env,
        capture_output=True,
        text=True,
        timeout=120,
    )


def test_install_creates_local_bin_when_missing(tmp_path):
    """Review 34: install.sh must mkdir -p ~/.local/bin before
    `dart compile exe -o ~/.local/bin/pdm-native-host`."""
    root = tmp_path / "pdm"
    host_bin = root / "integrations" / "browser-extension" / "host" / "bin"
    host_bin.mkdir(parents=True)
    (host_bin / "native_host.dart").write_text("// stub\n")
    dest = root / "integrations" / "browser-extension" / "install.sh"
    shutil.copy(
        REPO_ROOT / "integrations" / "browser-extension" / "install.sh",
        dest,
    )
    home = tmp_path / "home"
    home.mkdir()
    fakebin = tmp_path / "fakebin"
    fakebin.mkdir()
    # A fake dart that only writes the -o output file (like the real
    # `dart compile exe` would): it fails when the directory is missing.
    write_executable(
        fakebin / "dart",
        """\
        #!/bin/sh
        out=""
        prev=""
        for arg in "$@"; do
          if [ "$prev" = "-o" ]; then out="$arg"; fi
          prev="$arg"
        done
        [ -n "$out" ] || exit 1
        printf 'fake host\\n' > "$out"
        """,
    )
    result = run_script(
        dest,
        cwd=root,
        args=["abcdefghijklmnop"],
        env_extra={
            "HOME": str(home),
            "PATH": f"{fakebin}:{os.environ['PATH']}",
        },
    )
    assert result.returncode == 0, result.stdout + result.stderr
    assert (home / ".local" / "bin" / "pdm-native-host").is_file()
    chrome_manifest = (
        home
        / ".config"
        / "google-chrome"
        / "NativeMessagingHosts"
        / "com.ponta.pdm.json"
    )
    assert chrome_manifest.is_file()
    assert "chrome-extension://abcdefghijklmnop/" in chrome_manifest.read_text()
    firefox_manifest = (
        home / ".mozilla" / "native-messaging-hosts" / "com.ponta.pdm.json"
    )
    assert firefox_manifest.is_file()
    assert "pdm@ponta.dev" in firefox_manifest.read_text()
