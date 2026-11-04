#!/usr/bin/env python3
"""Build a self-contained Quickshell configuration with the local Qt tools."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def qt_tool(name: str) -> str:
    directories = [os.environ.get("QT_TOOLS_DIR", ""), "/usr/lib/qt6/bin",
                   "/usr/lib64/qt6/bin", "/usr/lib/qt6/libexec"]
    executable = shutil.which(name)
    if executable:
        return executable
    for directory in directories:
        candidate = Path(directory) / name
        if directory and candidate.is_file() and os.access(candidate, os.X_OK):
            return str(candidate)
    raise RuntimeError(f"Missing Qt tool {name}; set QT_TOOLS_DIR to the Qt 6 bin directory")


def verify_assets() -> dict:
    manifest = json.loads((ROOT / "assets/manifest.json").read_text())
    for name, entry in manifest.items():
        path = ROOT / "assets" / name
        if path.stat().st_size != entry["bytes"]:
            raise RuntimeError(f"Asset size mismatch: {name}")
        if hashlib.sha256(path.read_bytes()).hexdigest() != entry["sha256"]:
            raise RuntimeError(f"Asset checksum mismatch: {name}")
    return manifest


def baker_compatibility_arguments(executable: str) -> list[str]:
    # New Qt releases expose an explicit Qt 6 compatibility flag. Older
    # Qt 6 bakers already target Qt 6 and reject that option entirely.
    result = subprocess.run([executable, "--help"], capture_output=True, text=True, check=True)
    return ["--qt6"] if "--qt6" in result.stdout + result.stderr else []


def build(output: Path | None = None) -> Path:
    output = (output or ROOT / "build/runtime").resolve()
    manifest = verify_assets()
    baker = qt_tool("qsb")
    if output.exists() and not (output / ".planet-wallpaper-build").is_file():
        raise RuntimeError("Refusing to replace an unmarked build directory")
    compatibility = baker_compatibility_arguments(baker)
    output.parent.mkdir(parents=True, exist_ok=True)
    temporary = Path(tempfile.mkdtemp(prefix=".planet-build-", dir=output.parent))
    try:
        (temporary / ".planet-wallpaper-build").write_text("generated build\n")
        for source in (ROOT / "src").iterdir():
            if source.suffix in {".qml", ".frag"}:
                shutil.copy2(source, temporary / source.name)
        assets = temporary / "assets"
        assets.mkdir()
        for name in manifest:
            shutil.copy2(ROOT / "assets" / name, assets / name)
        shutil.copy2(ROOT / "assets/manifest.json", assets / "manifest.json")
        shutil.copy2(ROOT / "config/settings.example.json", temporary / "settings.json")
        tests = temporary / "weather-tests"
        tests.mkdir()
        test_output = (ROOT / "build/test-output").resolve().as_posix()
        for source in (ROOT / "tests/native").iterdir():
            if source.suffix in {".qml", ".frag"}:
                text = source.read_text().replace("@TEST_OUTPUT@", test_output)
                (tests / source.name).write_text(text)
        for shader in sorted(temporary.rglob("*.frag")):
            subprocess.run([baker, *compatibility, "-o", str(shader) + ".qsb", str(shader)], check=True)
        if output.exists():
            shutil.rmtree(output)
        temporary.rename(output)
    finally:
        if temporary.exists():
            shutil.rmtree(temporary)
    return output


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    print(build(args.output))


if __name__ == "__main__":
    main()
