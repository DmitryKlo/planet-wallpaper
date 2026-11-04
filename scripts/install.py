#!/usr/bin/env python3
"""Install the built wallpaper for the current user, preserving settings."""

from __future__ import annotations

import argparse
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def xdg_path(variable: str, fallback: str) -> Path:
    return Path(os.environ.get(variable) or Path.home() / fallback).expanduser().resolve()


def systemd_quote(value: str) -> str:
    return '"' + value.replace("\\", "\\\\").replace('"', '\\"').replace("%", "%%") + '"'


def install(config_home: Path, data_home: Path, bin_home: Path, *,
            runtime: Path | None = None, qs_binary: str | None = None,
            no_systemd: bool = False, start: bool = False) -> dict:
    runtime = runtime or ROOT / "build/runtime"
    if not (runtime / ".planet-wallpaper-build").is_file():
        raise RuntimeError("Run python3 scripts/build.py first")
    qs = qs_binary or shutil.which("qs") or shutil.which("quickshell")
    if not qs:
        raise RuntimeError("Quickshell is missing (expected qs or quickshell)")
    if start and no_systemd:
        raise ValueError("--start cannot be combined with --no-systemd")
    target = config_home / "quickshell/planet-wallpaper"
    unit = config_home / "systemd/user/planet-wallpaper.service"
    wrapper = bin_home / "planet-wallpaper"
    if target.is_symlink():
        raise RuntimeError("The installation target is a symlink; resolve it before installing")
    settings = target / "settings.json"
    retained = settings.read_bytes() if settings.exists() else None
    if retained is not None and not isinstance(json.loads(retained), dict):
        raise ValueError("Existing settings must be a JSON object")
    backup = None
    if any(path.exists() for path in (target, unit, wrapper)):
        stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S.%fZ")
        backup = data_home / "planet-wallpaper-install-backups" / stamp
        backup.mkdir(parents=True)
        for source, name in ((target, "runtime"), (unit, "planet-wallpaper.service"),
                             (wrapper, "planet-wallpaper")):
            if source.is_dir():
                shutil.copytree(source, backup / name)
            elif source.exists():
                shutil.copy2(source, backup / name)
    target.parent.mkdir(parents=True, exist_ok=True)
    temporary = Path(tempfile.mkdtemp(prefix=".planet-install-", dir=target.parent))
    previous = temporary / "previous"
    staged = temporary / "runtime"
    try:
        shutil.copytree(runtime, staged, ignore=shutil.ignore_patterns("weather-tests"))
        if retained is not None:
            (staged / "settings.json").write_bytes(retained)
        if target.exists():
            target.rename(previous)
        try:
            staged.rename(target)
        except BaseException:
            if previous.exists():
                previous.rename(target)
            raise
    finally:
        shutil.rmtree(temporary)
    bin_home.mkdir(parents=True, exist_ok=True)
    shutil.copy2(ROOT / "scripts/planet-wallpaper", wrapper)
    wrapper.chmod(0o755)
    unit.parent.mkdir(parents=True, exist_ok=True)
    unit.write_text("[Unit]\nDescription=Animated planet wallpaper\n"
                    "After=niri.service noctalia-shell.service\nPartOf=graphical-session.target\n\n"
                    "[Service]\nType=simple\nExecStart=" + systemd_quote(qs)
                    + " -p " + systemd_quote(str(target))
                    + "\nRestart=on-failure\nRestartSec=3\nNice=10\n\n"
                    "[Install]\nWantedBy=graphical-session.target\n")
    if not no_systemd:
        subprocess.run(["systemctl", "--user", "daemon-reload"], check=True)
        if start:
            subprocess.run(["systemctl", "--user", "enable", "--now", "planet-wallpaper.service"], check=True)
            subprocess.run(["systemctl", "--user", "restart", "planet-wallpaper.service"], check=True)
    return {"runtime": str(target), "wrapper": str(wrapper), "unit": str(unit),
            "settings_preserved": retained is not None, "backup": str(backup) if backup else None}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config-home", type=Path, default=xdg_path("XDG_CONFIG_HOME", ".config"))
    parser.add_argument("--data-home", type=Path, default=xdg_path("XDG_DATA_HOME", ".local/share"))
    parser.add_argument("--bin-home", type=Path, default=Path.home() / ".local/bin")
    parser.add_argument("--no-systemd", action="store_true", help="Write files without contacting systemd")
    parser.add_argument("--start", action="store_true", help="Enable and start the wallpaper service")
    args = parser.parse_args()
    print(json.dumps(install(args.config_home.expanduser().resolve(), args.data_home.expanduser().resolve(),
                             args.bin_home.expanduser().resolve(), no_systemd=args.no_systemd,
                             start=args.start), indent=2))


if __name__ == "__main__":
    main()
