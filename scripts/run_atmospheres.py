#!/usr/bin/env python3
"""Read back Venus/Saturn GPU states and render their atmosphere at fixed phase."""
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import subprocess
import time

import numpy as np
from PIL import Image

from build import ROOT, build, qt_tool


def pixels(path: Path) -> np.ndarray:
    return np.asarray(Image.open(path).convert("RGB"), dtype=np.int16)


def run_case(runtime: Path, output: Path, name: str, filename: str,
             arguments: list[str], environment: dict[str, str]) -> dict:
    print("Running", name, flush=True)
    command = [qt_tool("qml"), str(runtime / "weather-tests" / filename)]
    if arguments:
        command += ["--", *arguments]
    started = time.monotonic()
    result = subprocess.run(command, env=environment, capture_output=True, text=True, timeout=100)
    log = result.stdout + result.stderr
    (output / (name + ".log")).write_text(log)
    if result.returncode:
        raise RuntimeError(f"Native atmosphere check failed: {name}; see build/test-output/{name}.log")
    return {"returncode": result.returncode, "wallSeconds": round(time.monotonic() - started, 3)}


def verify_states(output: Path, planet: str) -> dict:
    folder = output / planet
    names = ("seed-a", "seed-b", "after-four-hours", "weather-off", "resumed-no-jump", "ten-times-time") \
        if planet == "venus" else ("seed", "reset-seed", "evolved", "paused", "resumed", "x10")
    seed, reset, evolved, held, resumed, fast = [pixels(folder / (name + ".png")) for name in names]
    assert np.array_equal(seed, reset), planet + ": reset changed the seed"
    assert not np.array_equal(seed, evolved), planet + ": atmosphere did not evolve"
    assert np.array_equal(evolved, held), planet + ": disabled atmosphere changed"
    assert np.array_equal(held, resumed), planet + ": atmosphere jumped on resume"
    assert not np.array_equal(resumed, fast), planet + ": x10 atmosphere did not evolve"
    return {"resetReproducible": True, "freezeExact": True, "resumeExact": True,
            "stateMeanDelta255": float(np.abs(seed - evolved).mean()),
            "x10StateMeanDelta255": float(np.abs(resumed - fast).mean())}


def verify_motion(folder: Path, planet: str) -> dict:
    first = pixels(folder / "frame-0000.png")
    third = pixels(folder / "frame-0045.png")
    final = pixels(folder / "frame-0090.png")
    height, width = first.shape[:2]
    yy, xx = np.indices((height, width))
    # Sphere bounds use the same normalized artwork coordinates as the visuals.
    center, radius = ((1.29, .555), .335) if planet == "venus" else ((1.20, .55), .235)
    aspect = 1672 / 941
    distance = np.hypot((xx + .5) / width * aspect - center[0], (yy + .5) / height - center[1])
    surface = distance < .92 * radius
    sky = distance > 1.05 * radius
    delta = np.max(np.abs(first - third), axis=2)
    late_delta = np.max(np.abs(first - final), axis=2)
    assert delta[sky].max() == 0, planet + ": sky moved with atmosphere"
    assert np.mean(delta[surface]) > .15, planet + ": imperceptible atmosphere at x10"
    changed = float(np.mean(delta[surface] > 2) * 100)
    assert changed > 2, (planet, changed)
    return {"speed": 10, "rotationFixed": True, "skyPixelMaxDelta": 0,
            "surfaceMeanDelta255After3Seconds": float(delta[surface].mean()),
            "surfacePercentChangedOver2LevelsAfter3Seconds": changed,
            "surfaceMeanDelta255After6Seconds": float(late_delta[surface].mean())}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--no-build", action="store_true", help="Use the existing marked runtime")
    args = parser.parse_args()
    runtime = ROOT / "build/runtime" if args.no_build else build()
    if not (runtime / ".planet-wallpaper-build").is_file():
        raise RuntimeError("Build the runtime first")
    output = ROOT / "build/test-output"
    output.mkdir(parents=True, exist_ok=True)
    environment = dict(os.environ, QT_QPA_PLATFORM="offscreen", QT_QUICK_BACKEND="rhi",
                       QSG_RHI_BACKEND="opengl", QT_FORCE_STDERR_LOGGING="1", QT_LOGGING_TO_CONSOLE="1")
    report = {}
    for planet in ("venus", "saturn"):
        (output / planet).mkdir(exist_ok=True)
        motion = output / (planet + "-motion")
        motion.mkdir(exist_ok=True)
        process = run_case(runtime, output, planet + "-state", planet.capitalize() + "AtmosphereTest.qml", [], environment)
        state = verify_states(output, planet)
        render = run_case(runtime, output, planet + "-motion", "AtmosphereMotion.qml",
                          ["--planet=" + planet, "--output=" + str(motion)], environment)
        report[planet] = {"state": state, "motion": verify_motion(motion, planet),
                          "processes": {"state": process, "motion": render}}
        (output / "atmospheres-report.json").write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()
