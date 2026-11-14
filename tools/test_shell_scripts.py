"""Behavioural tests for the repo's shell scripts (review items 34, 35, 38).

Run: pytest tools/test_shell_scripts.py

Each test copies the real script into a temp layout and runs it with
fake tools on PATH, so no network and no real binaries are involved.
"""
import gzip
import hashlib
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
    # The bundled JavaScript runtime: yt-dlp needs it for YouTube.
    write_executable(
        bin_dir / "qjs",
        """\
        #!/bin/sh
        if [ "$1" = "--version" ]; then echo "0.18.0"; exit 0; fi
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
    assert "qjs already present, skipping" in result.stdout
    assert not curl_log.exists(), "the script tried to download"


FAKE_FFMPEG = (
    b"#!/bin/sh\n"
    b'if [ "$1" = "-version" ]; then echo "ffmpeg version fake"; exit 0; fi\n'
    b"exit 8\n"
)
FAKE_YTDLP = (
    b"#!/bin/sh\n"
    b'if [ "$1" = "--version" ]; then echo "2026.01.01"; exit 0; fi\n'
    b"exit 1\n"
)
# quickjs-ng's qjs prints its version for --version and exits 0.
FAKE_QJS = (
    b"#!/bin/sh\n"
    b'if [ "$1" = "--version" ]; then echo "0.18.0"; exit 0; fi\n'
    b"exit 1\n"
)
# The digests the script pins for its two ffmpeg assets. The tests
# rewrite them to the fixture's digest: the pin is the whole point of
# the asset check, but a fixture can never be the real 80 MB binary.
PINNED_FFMPEG_SHA256 = (
    "bfe8a8fc511530457b528c48d77b5737527b504a3797a9bc4866aeca69c2dffa",
    "8883a3dffbd0a16cf4ef95206ea05283f78908dbfb118f73c83f4951dcc06d77",
)
# The digests the script pins for the quickjs assets, rewritten for the
# same reason: the real binaries are 1.9-2.5 MB.
PINNED_QJS_SHA256 = (
    "85ded23b9fabe8c1644fc40a8d2bbdd71157affcbd807359c618cc717ee24d7d",
    "ff03398d74ea6e6bd3a8e58058f7003225abcac229d7d57775b7aaae812a49c7",
)


def fetch_layout(tmp_path, curl_body, pinned_ffmpeg_sha256=None,
                 pinned_qjs_sha256=None):
    """Builds a temp repo layout with the script and a fake curl.

    Returns (root, script, bin_dir, curl_log, fakebin). `curl_body` is
    the body of the fake curl and sees `$out`, `$url` and the log path.
    `pinned_ffmpeg_sha256` / `pinned_qjs_sha256` replace every digest
    the script pins for an asset of that tool, so a fixture can pass
    the check without the real bytes; pass None to leave the real pins
    in place.
    """
    root = tmp_path / "pdm"
    tools_dir = root / "tools"
    tools_dir.mkdir(parents=True)
    script = tools_dir / "fetch_external_tools.sh"
    shutil.copy(REPO_ROOT / "tools" / "fetch_external_tools.sh", script)
    text = script.read_text()
    for pins, replacement in (
        (PINNED_FFMPEG_SHA256, pinned_ffmpeg_sha256),
        (PINNED_QJS_SHA256, pinned_qjs_sha256),
    ):
        if replacement is None:
            continue
        for pin in pins:
            assert pin in text, pin
            text = text.replace(pin, replacement)
    script.write_text(text)
    fakebin = tmp_path / "fakebin"
    fakebin.mkdir()
    curl_log = tmp_path / "curl.log"
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
        {curl_body}
        """,
    )
    return (
        root,
        script,
        root / "apps" / "desktop" / "bundle" / "bin",
        curl_log,
        fakebin,
    )


def ffmpeg_gz_fixture(tmp_path):
    """A gzip'd fake ffmpeg, like the pinned GitHub asset."""
    path = tmp_path / "ffmpeg-linux-x64.gz"
    path.write_bytes(gzip.compress(FAKE_FFMPEG))
    return path


def sha256_of(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def ytdlp_fixture(tmp_path):
    path = tmp_path / "yt-dlp_linux"
    path.write_bytes(FAKE_YTDLP)
    return path


def qjs_fixture(tmp_path, name="qjs-linux-x86_64", data=FAKE_QJS):
    path = tmp_path / name
    path.write_bytes(data)
    return path


def sums_fixture(tmp_path, asset, data):
    path = tmp_path / "SHA2-256SUMS"
    digest = hashlib.sha256(data).hexdigest()
    path.write_text(f"{digest}  {asset}\n")
    return path


class FakeGitHub:
    """Fake curl body that serves fixtures for the GitHub assets.

    `fail_on` is a set of URL substrings whose downloads fail, so a
    test can force the mirror fallbacks. `fail_direct` makes every
    download straight from github.com fail, like a throttled runner.
    """

    def __init__(self, tmp_path, sums, ffmpeg_gz, ytdlp, qjs=None,
                 fail_on=(), fail_direct=False):
        self.sums = sums
        self.ffmpeg_gz = ffmpeg_gz
        self.ytdlp = ytdlp
        self.qjs = qjs
        self.fail_on = fail_on
        self.fail_direct = fail_direct

    def body(self):
        # Unquoted patterns so `case` globs on them.
        fail = " | ".join(f"*{s}*" for s in self.fail_on) or "''"
        direct = (
            '  https://github.com/*) rm -f "$out"; exit 22 ;;\n'
            if self.fail_direct
            else ""
        )
        qjs = (
            f'  *qjs-linux-x86_64|*qjs-windows-x86_64.exe) '
            f'cat "{self.qjs}" > "$out" ;;\n'
            if self.qjs
            else ""
        )
        return f"""\
        case "$url" in
          {fail}) rm -f "$out"; exit 22 ;;
        esac
        case "$url" in
{direct}          *SHA2-256SUMS*) cat "{self.sums}" > "$out" ;;
          *ffmpeg*.gz) cat "{self.ffmpeg_gz}" > "$out" ;;
          *yt-dlp_linux|*yt-dlp.exe) cat "{self.ytdlp}" > "$out" ;;
{qjs}          *) rm -f "$out"; exit 22 ;;
        esac
        """


def test_fetch_downloads_binaries_on_clean_clone(tmp_path):
    """Review 38: on a clean clone (no bundle/bin at all) the fetch
    script must download both binaries and leave working ones behind.
    A fake curl serves the fixtures, so no network is involved."""
    ffmpeg_gz = ffmpeg_gz_fixture(tmp_path)
    ytdlp = ytdlp_fixture(tmp_path)
    qjs = qjs_fixture(tmp_path)
    sums = sums_fixture(tmp_path, "yt-dlp_linux", FAKE_YTDLP)
    fake = FakeGitHub(tmp_path, sums, ffmpeg_gz, ytdlp, qjs)
    root, script, bin_dir, curl_log, fakebin = fetch_layout(
        tmp_path, fake.body(),
        pinned_ffmpeg_sha256=sha256_of(ffmpeg_gz),
        pinned_qjs_sha256=sha256_of(qjs),
    )
    assert not bin_dir.exists(), "clean clone must have no bundle/bin"

    result = run_script(
        script,
        cwd=root,
        args=["linux"],
        env_extra={"PATH": f"{fakebin}:{os.environ['PATH']}"},
    )
    assert result.returncode == 0, result.stdout + result.stderr
    assert "already present, skipping" not in result.stdout
    urls = curl_log.read_text().splitlines()
    # The checksum goes direct, the assets go through a mirror.
    assert any(u.startswith("https://github.com/")
               and "SHA2-256SUMS" in u for u in urls), urls
    assert any(u.startswith("https://ghfast.top/https://github.com/")
               and "ffmpeg-linux-x64.gz" in u for u in urls), urls
    assert any(u.startswith("https://ghfast.top/https://github.com/")
               and "yt-dlp_linux" in u for u in urls), urls
    assert any(u.startswith("https://ghfast.top/https://github.com/")
               and "qjs-linux-x86_64" in u for u in urls), urls

    ffmpeg = bin_dir / "ffmpeg"
    ytdlp_bin = bin_dir / "yt-dlp"
    qjs_bin = bin_dir / "qjs"
    assert ffmpeg.is_file() and os.access(ffmpeg, os.X_OK)
    assert ytdlp_bin.is_file() and os.access(ytdlp_bin, os.X_OK)
    # yt-dlp looks the runtime up by exactly this name.
    assert qjs_bin.is_file() and os.access(qjs_bin, os.X_OK)
    assert (bin_dir / "ffmpeg.version").read_text().startswith(
        "ffmpeg version fake"
    )
    assert (bin_dir / "yt-dlp.version").read_text().startswith("2026.01.01")
    assert (bin_dir / "qjs.version").read_text().startswith("0.18.0")
    probe = subprocess.run(
        [str(ffmpeg), "-version"], capture_output=True, text=True
    )
    assert probe.returncode == 0
    assert "ffmpeg version fake" in probe.stdout
    probe = subprocess.run(
        [str(ytdlp_bin), "--version"], capture_output=True, text=True
    )
    assert probe.returncode == 0
    assert "2026.01.01" in probe.stdout
    probe = subprocess.run(
        [str(qjs_bin), "--version"], capture_output=True, text=True
    )
    assert probe.returncode == 0
    assert "0.18.0" in probe.stdout


def test_fetch_falls_back_to_the_next_mirror(tmp_path):
    """A mirror that fails or stalls must not sink the job: the script
    moves to the next mirror, then to github.com itself."""
    ffmpeg_gz = ffmpeg_gz_fixture(tmp_path)
    ytdlp = ytdlp_fixture(tmp_path)
    qjs = qjs_fixture(tmp_path)
    sums = sums_fixture(tmp_path, "yt-dlp_linux", FAKE_YTDLP)
    fake = FakeGitHub(
        tmp_path, sums, ffmpeg_gz, ytdlp, qjs,
        fail_on=("ghfast.top",), fail_direct=True,
    )
    root, script, bin_dir, curl_log, fakebin = fetch_layout(
        tmp_path, fake.body(),
        pinned_ffmpeg_sha256=sha256_of(ffmpeg_gz),
        pinned_qjs_sha256=sha256_of(qjs),
    )
    result = run_script(
        script,
        cwd=root,
        args=["linux"],
        env_extra={"PATH": f"{fakebin}:{os.environ['PATH']}"},
    )
    assert result.returncode == 0, result.stdout + result.stderr
    urls = curl_log.read_text().splitlines()
    assert any("ghfast.top" in u for u in urls), urls
    assert any(u.startswith("https://gh-proxy.com/") for u in urls), urls
    # Checksums prefer a direct GitHub fetch and only fall back to a
    # mirror when that fails.
    assert any(u == "https://github.com/yt-dlp/yt-dlp/releases/latest/"
                    "download/SHA2-256SUMS" for u in urls), urls
    assert any(u.startswith("https://gh-proxy.com/https://github.com/")
               and "SHA2-256SUMS" in u for u in urls), urls
    assert (bin_dir / "ffmpeg").is_file()
    assert (bin_dir / "yt-dlp").is_file()
    assert (bin_dir / "qjs").is_file()


def test_fetch_rejects_an_asset_that_fails_its_checksum(tmp_path):
    """A mirror is a third party: a truncated or rewritten asset must
    not be installed. When every candidate serves bytes that miss the
    expected digest the script fails instead of leaving a broken binary
    behind."""
    ytdlp = ytdlp_fixture(tmp_path)
    sums = sums_fixture(tmp_path, "yt-dlp_linux", FAKE_YTDLP)
    # Bytes that match neither the pinned ffmpeg digest nor the sums.
    tampered = tmp_path / "tampered.gz"
    tampered.write_bytes(gzip.compress(b"#!/bin/sh\nexit 0\n"))

    root, script, bin_dir, _curl_log, fakebin = fetch_layout(
        tmp_path, FakeGitHub(tmp_path, sums, tampered, ytdlp).body()
    )
    result = run_script(
        script,
        cwd=root,
        args=["linux"],
        env_extra={"PATH": f"{fakebin}:{os.environ['PATH']}"},
    )
    assert result.returncode != 0, result.stdout + result.stderr
    assert "checksum mismatch" in result.stderr
    assert not (bin_dir / "ffmpeg").exists()
    assert not (bin_dir / "yt-dlp").exists()


def test_fetch_accepts_a_windows_qjs_exe(tmp_path):
    """Windows gets its own qjs asset, installed under the name yt-dlp
    looks for. The host cannot run it, so it is not version-checked."""
    sums = sums_fixture(tmp_path, "yt-dlp.exe", FAKE_YTDLP)
    qjs_exe = b"MZ fake qjs.exe"
    qjs = qjs_fixture(tmp_path, "qjs-windows-x86_64.exe", qjs_exe)
    ffmpeg_exe = b"MZ fake ffmpeg.exe"
    ffmpeg_gz = tmp_path / "ffmpeg-win32-x64.gz"
    ffmpeg_gz.write_bytes(gzip.compress(ffmpeg_exe))
    ytdlp = ytdlp_fixture(tmp_path)
    fake = FakeGitHub(tmp_path, sums, ffmpeg_gz, ytdlp, qjs)
    root, script, bin_dir, _curl_log, fakebin = fetch_layout(
        tmp_path, fake.body(),
        pinned_ffmpeg_sha256=sha256_of(ffmpeg_gz),
        pinned_qjs_sha256=sha256_of(qjs),
    )
    result = run_script(
        script,
        cwd=root,
        args=["windows"],
        env_extra={"PATH": f"{fakebin}:/usr/bin:/bin"},
    )
    assert result.returncode == 0, result.stdout + result.stderr
    assert (bin_dir / "qjs.exe").read_bytes() == qjs_exe


def test_fetch_windows_uses_the_pinned_ffmpeg_without_unzip(tmp_path):
    """The Windows ffmpeg is the pinned gzip'd GitHub asset, not a
    gyan.dev zip: that keeps both platforms on one mirror-and-digest
    path, and drops the unzip dependency from Windows CI."""
    sums = sums_fixture(tmp_path, "yt-dlp.exe", FAKE_YTDLP)
    ffmpeg_exe = b"MZ fake ffmpeg.exe"
    ffmpeg_gz = tmp_path / "ffmpeg-win32-x64.gz"
    ffmpeg_gz.write_bytes(gzip.compress(ffmpeg_exe))
    ytdlp = ytdlp_fixture(tmp_path)
    qjs_exe = b"MZ fake qjs.exe"
    qjs = qjs_fixture(tmp_path, "qjs-windows-x86_64.exe", qjs_exe)
    fake = FakeGitHub(tmp_path, sums, ffmpeg_gz, ytdlp, qjs)
    root, script, bin_dir, _curl_log, fakebin = fetch_layout(
        tmp_path, fake.body(),
        pinned_ffmpeg_sha256=sha256_of(ffmpeg_gz),
        pinned_qjs_sha256=sha256_of(qjs),
    )
    result = run_script(
        script,
        cwd=root,
        args=["windows"],
        # No unzip on PATH: the script must not need it.
        env_extra={
            "PATH": f"{fakebin}:/usr/bin:/bin",
        },
    )
    assert result.returncode == 0, result.stdout + result.stderr
    assert (bin_dir / "ffmpeg.exe").read_bytes() == ffmpeg_exe
    assert (bin_dir / "yt-dlp.exe").read_bytes() == FAKE_YTDLP
