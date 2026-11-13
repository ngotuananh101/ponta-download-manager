"""Tests for packaging/windows/generate_wix_files.py.

Run: pytest tools/test_wix_files.py

The generator runs on a Windows runner, so the regression this file
guards is separator handling: building Directory ids must not depend
on the host's pathlib flavour. The Windows behaviour is reproduced by
swapping the module's Path for PureWindowsPath.
"""

import collections
import importlib.util
import pathlib

import pytest

REPO_ROOT = pathlib.Path(__file__).resolve().parent.parent
GENERATOR = REPO_ROOT / "packaging" / "windows" / "generate_wix_files.py"


def load_generator():
    spec = importlib.util.spec_from_file_location("generate_wix_files", GENERATOR)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


BUNDLE = {
    # Flutter's release bundle layout, Windows flavour.
    "pdm.exe": None,
    "data/icudtl.dat": None,
    "data/flutter_assets/AssetManifest.bin": None,
    "data/flutter_assets/assets/images/icon.png": None,
    "data/flutter_assets/fonts/MaterialIcons-Regular.otf": None,
    "data/flutter_assets/packages/cupertino_icons/assets/CupertinoIcons.ttf": None,
    "data/flutter_assets/shaders/ink_sparkle.frag": None,
    "bin/ffmpeg.exe": None,
    "bin/yt-dlp.exe": None,
    "lib/libapp.so": None,
}


def make_bundle(root):
    for rel in BUNDLE:
        path = root / rel
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(b"")
    return root


@pytest.fixture
def gen(monkeypatch):
    module = load_generator()
    # Pretend the host is Windows: this is what broke the generator.
    monkeypatch.setattr(module, "Path", pathlib.PureWindowsPath)
    return module


def test_collect_emits_posix_paths_only(gen, tmp_path):
    directories, files = gen.collect(make_bundle(tmp_path))
    for rel in directories:
        assert "\\" not in rel, rel
    for rel, parent in files:
        assert "\\" not in rel, rel
        assert "\\" not in parent, (rel, parent)


def test_collect_directory_ids_are_unique(gen, tmp_path):
    directories, _ = gen.collect(make_bundle(tmp_path))
    ids = [gen.dir_id(d) for d in directories]
    duplicates = [i for i, n in collections.Counter(ids).items() if n > 1]
    assert duplicates == []


def test_collect_keeps_every_file(gen, tmp_path):
    _, files = gen.collect(make_bundle(tmp_path))
    assert sorted(rel for rel, _ in files) == sorted(BUNDLE)


def test_collect_parents_exist_as_directories(gen, tmp_path):
    directories, files = gen.collect(make_bundle(tmp_path))
    known = set(directories)
    for rel, parent in files:
        if parent:
            assert parent in known, f"{rel} has parent {parent} not in {sorted(known)}"


def test_rendered_fragment_has_no_duplicate_ids(gen, tmp_path):
    directories, files = gen.collect(make_bundle(tmp_path))
    xml = gen.render(tmp_path, directories, files)
    ids = [line.split('Id="', 1)[1].split('"', 1)[0]
           for line in xml.splitlines() if "<Directory " in line]
    duplicates = [i for i, n in collections.Counter(ids).items() if n > 1]
    assert duplicates == []
