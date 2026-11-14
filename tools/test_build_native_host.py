"""Behavioural tests for tools/build_native_host.sh.

Run: pytest tools/test_build_native_host.py

The script only wraps `dart compile exe`, so the tests drive it with a fake
`dart` on PATH and assert on where the output lands — the part the app and
the packaging rules depend on.
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


def layout(tmp_path):
    """A temp repo with the host sources and the build script."""
    root = tmp_path / "pdm"
    host_bin = root / "integrations" / "browser-extension" / "host" / "bin"
    host_bin.mkdir(parents=True)
    (host_bin / "native_host.dart").write_text("// stub\n")
    tools_dir = root / "tools"
    tools_dir.mkdir(parents=True)
    script = tools_dir / "build_native_host.sh"
    shutil.copy(REPO_ROOT / "tools" / "build_native_host.sh", script)
    fakebin = tmp_path / "fakebin"
    fakebin.mkdir()
    # A fake dart that records its arguments and writes the -o output, the
    # way `dart compile exe` does.
    log = tmp_path / "dart.log"
    write_executable(
        fakebin / "dart",
        f"""\
        #!/bin/sh
        echo "$@" >> "{log}"
        out=""
        prev=""
        for arg in "$@"; do
          if [ "$prev" = "-o" ]; then out="$arg"; fi
          prev="$arg"
        done
        [ -n "$out" ] || exit 1
        mkdir -p "$(dirname "$out")"
        printf 'fake host\\n' > "$out"
        """,
    )
    return root, script, fakebin, log


def run(script, root, fakebin, args=()):
    env = dict(os.environ)
    env["PATH"] = f"{fakebin}:{env['PATH']}"
    # uname is used to pick the default target; pin it so the test says the
    # same thing on every host.
    fake_uname = fakebin / "uname"
    write_executable(fake_uname, "#!/bin/sh\necho Linux\n")
    return subprocess.run(
        ["bash", str(script), *args],
        cwd=root,
        env=env,
        capture_output=True,
        text=True,
        timeout=120,
    )


def test_builds_the_linux_host_into_the_bundle(tmp_path):
    root, script, fakebin, log = layout(tmp_path)

    result = run(script, root, fakebin, ["linux"])

    assert result.returncode == 0, result.stdout + result.stderr
    host = root / "apps" / "desktop" / "bundle" / "bin" / "pdm-native-host"
    assert host.is_file()
    args = log.read_text()
    assert "compile exe" in args
    assert "integrations/browser-extension/host/bin/native_host.dart" in args


def test_builds_the_windows_host_with_the_exe_suffix(tmp_path):
    # The manifest path the app writes has to match the file that exists:
    # Chrome on Windows will not run a host binary without the suffix.
    root, script, fakebin, _ = layout(tmp_path)

    result = run(script, root, fakebin, ["windows"])

    assert result.returncode == 0, result.stdout + result.stderr
    host = root / "apps" / "desktop" / "bundle" / "bin" / "pdm-native-host.exe"
    assert host.is_file()


def test_defaults_to_the_host_platform(tmp_path):
    root, script, fakebin, _ = layout(tmp_path)

    result = run(script, root, fakebin)

    assert result.returncode == 0, result.stdout + result.stderr
    host = root / "apps" / "desktop" / "bundle" / "bin" / "pdm-native-host"
    assert host.is_file()


def test_rejects_an_unknown_target(tmp_path):
    # Silently building the wrong platform would put a binary in the bundle
    # that the other platform cannot execute.
    root, script, fakebin, _ = layout(tmp_path)

    result = run(script, root, fakebin, ["macos"])

    assert result.returncode == 2
    assert "unknown target" in result.stderr
    assert not (root / "apps" / "desktop" / "bundle").exists()
