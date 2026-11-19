"""Exercise the real build wrapper with Git fixtures and a fake Flutter boundary."""
import json
import os
import re
import shutil
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parent.parent


def git(root, *args):
    return subprocess.check_output(["git", "-C", str(root), *args], text=True).strip()


@pytest.fixture
def build_repo(tmp_path):
    root = tmp_path / "checkout with spaces"
    (root / "tools").mkdir(parents=True)
    (root / "apps" / "desktop").mkdir(parents=True)
    script = root / "tools" / "build_desktop.py"
    source = REPO_ROOT / "tools" / "build_desktop.py"
    if source.exists():
        shutil.copy(source, script)
    (root / "tracked.txt").write_text("original\n")
    shutil.copy(REPO_ROOT / ".gitignore", root / ".gitignore")
    git(root, "init", "-q")
    git(root, "add", ".")
    git(root, "-c", "user.name=Test", "-c", "user.email=test@example.invalid",
        "commit", "-qm", "fixture")
    fakebin = tmp_path / "fakebin"
    fakebin.mkdir()
    log = tmp_path / "flutter.json"
    flutter = fakebin / "flutter"
    flutter.write_text(
        f"#!{sys.executable}\n"
        "import json, os, sys\n"
        "from pathlib import Path\n"
        "Path(os.environ['FLUTTER_LOG']).write_text(json.dumps({"
        "'args': sys.argv[1:], 'cwd': os.getcwd()}))\n"
        "sys.exit(int(os.environ.get('FLUTTER_EXIT', '0')))\n"
    )
    flutter.chmod(0o755)
    env = dict(os.environ, PATH=f"{fakebin}{os.pathsep}{os.environ['PATH']}",
               FLUTTER_LOG=str(log))
    return root, script, env, log


def run(build_repo, target, **env_updates):
    root, script, env, _ = build_repo
    return subprocess.run(
        [sys.executable, "-I", str(script), target], cwd=root.parent,
        env=dict(env, **env_updates), capture_output=True, text=True, timeout=20,
    )


@pytest.mark.parametrize("target", ["linux", "windows"])
def test_stamps_head_and_utc_time_into_release_from_any_directory(build_repo, target):
    root, _, _, log = build_repo
    before = datetime.now(timezone.utc)
    result = run(build_repo, target)
    after = datetime.now(timezone.utc)
    assert result.returncode == 0, result.stderr
    invocation = json.loads(log.read_text())
    assert invocation["cwd"] == str(root / "apps" / "desktop")
    args = invocation["args"]
    assert args[:3] == ["build", target, "--release"]
    assert f"--dart-define=PDM_BUILD_COMMIT={git(root, 'rev-parse', 'HEAD')}" in args
    time_arg = next(a for a in args if a.startswith("--dart-define=PDM_BUILD_TIME="))
    stamp = datetime.fromisoformat(time_arg.split("=", 2)[2].replace("Z", "+00:00"))
    assert stamp.utcoffset().total_seconds() == 0
    assert before <= stamp <= after
    assert len(args) == 5


@pytest.mark.parametrize("staged", [False, True])
def test_marks_modified_tracked_sources_dirty(build_repo, staged):
    root, _, _, log = build_repo
    (root / "tracked.txt").write_text("modified\n")
    if staged:
        git(root, "add", "tracked.txt")
    result = run(build_repo, "linux")
    assert result.returncode == 0, result.stderr
    assert (f"--dart-define=PDM_BUILD_COMMIT={git(root, 'rev-parse', 'HEAD')} (dirty)"
            in json.loads(log.read_text())["args"])


@pytest.mark.parametrize("source", [
    "apps/desktop/lib/new_feature.dart",
    "integrations/browser-extension/extension/new_feature.js",
])
def test_untracked_sources_mark_commit_dirty(build_repo, source):
    root, _, _, log = build_repo
    file = root / source
    file.parent.mkdir(parents=True, exist_ok=True)
    file.write_text("// new source\n")
    result = run(build_repo, "linux")
    assert result.returncode == 0, result.stderr
    assert (f"--dart-define=PDM_BUILD_COMMIT={git(root, 'rev-parse', 'HEAD')} (dirty)"
            in json.loads(log.read_text())["args"])


def test_untracked_build_outputs_do_not_mark_commit_dirty(build_repo):
    root, _, _, log = build_repo
    file = root / "apps" / "desktop" / "build" / "artifact.zip"
    file.parent.mkdir(parents=True)
    file.write_bytes(b"build output")
    result = run(build_repo, "linux")
    assert result.returncode == 0, result.stderr
    assert f"--dart-define=PDM_BUILD_COMMIT={git(root, 'rev-parse', 'HEAD')}" in json.loads(log.read_text())["args"]


def test_rejects_unknown_target_before_flutter(build_repo):
    result = run(build_repo, "macos")
    assert result.returncode == 2
    assert not build_repo[3].exists()


def test_git_failure_prevents_unstamped_build(build_repo):
    root, _, _, log = build_repo
    shutil.rmtree(root / ".git")
    result = run(build_repo, "linux")
    assert result.returncode != 0
    assert "metadata" in result.stderr.lower()
    assert not log.exists()


def test_propagates_flutter_failure(build_repo):
    result = run(build_repo, "linux", FLUTTER_EXIT="17")
    assert result.returncode == 17


@pytest.mark.parametrize("target", ["linux", "windows"])
def test_ci_build_step_produces_stamped_release(build_repo, target):
    # Execute the build step's command, not merely assert on YAML source text.
    workflow = (REPO_ROOT / ".github" / "workflows" / "release.yml").read_text()
    block = re.search(rf"      - name: Build {target.title()}\n(.*?)(?=\n      - )",
                      workflow, re.S).group(1)
    command = re.search(r"        run: (.+)", block).group(1)
    directory = re.search(r"        working-directory: (.+)", block)
    root, _, env, log = build_repo
    cwd = root / directory.group(1) if directory else root
    result = subprocess.run(command, shell=True, cwd=cwd, env=env,
                            capture_output=True, text=True, timeout=20)
    assert result.returncode == 0, result.stderr
    args = json.loads(log.read_text())["args"]
    assert args[:3] == ["build", target, "--release"]
    assert f"--dart-define=PDM_BUILD_COMMIT={git(root, 'rev-parse', 'HEAD')}" in args
    assert any(a.startswith("--dart-define=PDM_BUILD_TIME=") for a in args)
