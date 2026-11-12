"""Behavioural tests for the repo's shell scripts (review items 34, 35, 38).

Run: pytest tools/test_shell_scripts.py

Each test copies the real script into a temp layout and runs it with
fake tools on PATH, so no network and no real binaries are involved.
"""
import io
import lzma
import os
import shutil
import stat
import subprocess
import tarfile
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


def test_fetch_skips_binaries_that_already_work(tmp_path):
    """Review 35: linux_usable must use each tool's own version flag.
    ffmpeg takes -version (--version exits 8), so probing it with
    --version always 'fails' and the script re-downloads every time."""
    root = tmp_path / "pdm"
    bin_dir = root / "apps" / "desktop" / "bundle" / "bin"
    bin_dir.mkdir(parents=True)
    tools_dir = root / "tools"
    tools_dir.mkdir(parents=True)
    shutil.copy(
        REPO_ROOT / "tools" / "fetch_external_tools.sh",
        tools_dir / "fetch_external_tools.sh",
    )
    # A fake ffmpeg behaving like the real one: -version exits 0,
    # --version exits 8.
    write_executable(
        bin_dir / "ffmpeg",
        """\
        #!/bin/sh
        if [ "$1" = "-version" ]; then echo "ffmpeg version fake"; exit 0; fi
        echo "ffmpeg fake: unknown option" >&2
        exit 8
        """,
    )
    write_executable(
        bin_dir / "yt-dlp",
        """\
        #!/bin/sh
        if [ "$1" = "--version" ]; then echo "2026.01.01"; exit 0; fi
        exit 1
        """,
    )
    fakebin = tmp_path / "fakebin"
    fakebin.mkdir()
    curl_log = tmp_path / "curl.log"
    # A fake curl that records any download attempt and fails it.
    write_executable(
        fakebin / "curl",
        f"""\
        #!/bin/sh
        echo "$@" >> "{curl_log}"
        exit 1
        """,
    )
    result = run_script(
        tools_dir / "fetch_external_tools.sh",
        cwd=root,
        args=["linux"],
        env_extra={"PATH": f"{fakebin}:{os.environ['PATH']}"},
    )
    assert result.returncode == 0, result.stdout + result.stderr
    assert "ffmpeg already present, skipping" in result.stdout
    assert "yt-dlp already present, skipping" in result.stdout
    assert not curl_log.exists(), "the script tried to download"

def test_fetch_downloads_binaries_on_clean_clone(tmp_path):
    """Review 38: on a clean clone (no bundle/bin at all) the fetch
    script must download both binaries and leave working ones behind.
    A fake curl serves the fixtures, so no network is involved: a
    .tar.xz holding a fake ffmpeg, and a fake yt-dlp script."""
    root = tmp_path / "pdm"
    tools_dir = root / "tools"
    tools_dir.mkdir(parents=True)
    shutil.copy(
        REPO_ROOT / "tools" / "fetch_external_tools.sh",
        tools_dir / "fetch_external_tools.sh",
    )
    bin_dir = root / "apps" / "desktop" / "bundle" / "bin"
    assert not bin_dir.exists(), "clean clone must have no bundle/bin"

    # Fixture 1: a .tar.xz holding a fake ffmpeg, like the real
    # johnvansickle static build (binary nested one level deep).
    fake_ffmpeg = (
        b"#!/bin/sh\n"
        b'if [ "$1" = "-version" ]; then echo "ffmpeg version fake"; exit 0; fi\n'
        b"exit 8\n"
    )
    buf = io.BytesIO()
    with tarfile.open(fileobj=buf, mode="w:xz") as tf:
        info = tarfile.TarInfo("ffmpeg-7.0.2-amd64-static/ffmpeg")
        info.size = len(fake_ffmpeg)
        info.mode = 0o755
        tf.addfile(info, io.BytesIO(fake_ffmpeg))
    ffmpeg_fixture = tmp_path / "ffmpeg.tar.xz"
    ffmpeg_fixture.write_bytes(buf.getvalue())

    # Fixture 2: a fake yt-dlp, served as the standalone binary.
    ytdlp_fixture = tmp_path / "yt-dlp"
    write_executable(
        ytdlp_fixture,
        """\
        #!/bin/sh
        if [ "$1" = "--version" ]; then echo "2026.01.01"; exit 0; fi
        exit 1
        """,
    )

    fakebin = tmp_path / "fakebin"
    fakebin.mkdir()
    curl_log = tmp_path / "curl.log"
    # A fake curl that serves the fixtures into the -o target instead
    # of hitting the network.
    write_executable(
        fakebin / "curl",
        f"""\
        #!/bin/sh
        out=""
        prev=""
        url=""
        for arg in "$@"; do
          if [ "$prev" = "-o" ]; then out="$arg"; fi
          prev="$arg"
          url="$arg"
        done
        echo "$url" >> "{curl_log}"
        case "$url" in
          *johnvansickle*) cat "$FFMPEG_FIXTURE" > "$out" ;;
          *yt-dlp*) cat "$YTDLP_FIXTURE" > "$out" ;;
          *) exit 1 ;;
        esac
        """,
    )
    result = run_script(
        tools_dir / "fetch_external_tools.sh",
        cwd=root,
        args=["linux"],
        env_extra={
            "PATH": f"{fakebin}:{os.environ['PATH']}",
            "FFMPEG_FIXTURE": str(ffmpeg_fixture),
            "YTDLP_FIXTURE": str(ytdlp_fixture),
        },
    )
    assert result.returncode == 0, result.stdout + result.stderr
    assert "already present, skipping" not in result.stdout
    assert curl_log.is_file()
    urls = curl_log.read_text().splitlines()
    assert len(urls) == 2, urls
    assert any("johnvansickle" in u for u in urls)
    assert any("yt-dlp" in u for u in urls)

    ffmpeg = bin_dir / "ffmpeg"
    ytdlp = bin_dir / "yt-dlp"
    assert ffmpeg.is_file() and os.access(ffmpeg, os.X_OK)
    assert ytdlp.is_file() and os.access(ytdlp, os.X_OK)
    assert (bin_dir / "ffmpeg.version").read_text().startswith(
        "ffmpeg version fake"
    )
    assert (bin_dir / "yt-dlp.version").read_text().startswith("2026.01.01")
    probe = subprocess.run(
        [str(ffmpeg), "-version"], capture_output=True, text=True
    )
    assert probe.returncode == 0
    assert "ffmpeg version fake" in probe.stdout
    probe = subprocess.run(
        [str(ytdlp), "--version"], capture_output=True, text=True
    )
    assert probe.returncode == 0
    assert "2026.01.01" in probe.stdout

