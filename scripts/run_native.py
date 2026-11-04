#!/usr/bin/env python3
"""Run the native weather checks without changing the running desktop."""

from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import subprocess
import time

from build import ROOT, build, qt_tool


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--full", action="store_true", help="Include coverage, clocks and a motion sequence")
    args = parser.parse_args()
    runtime = build()
    output = ROOT / "build/test-output"
    folders = ("model", "condensate-test", "toggle", "late-coverage", "clock-x1", "clock-x10", "motion-fixed")
    for name in folders:
        (output / name).mkdir(parents=True, exist_ok=True)
    environment = dict(os.environ, QT_QPA_PLATFORM="offscreen", QT_QUICK_BACKEND="rhi",
                       QSG_RHI_BACKEND="opengl", QT_FORCE_STDERR_LOGGING="1", QT_LOGGING_TO_CONSOLE="1")
    cases = [("condensate", "CondensateTest.qml", []), ("model", "StateTest.qml", []),
             ("toggle", "ToggleTest.qml", [])]
    if args.full:
        cases += [("coverage", "LateCoverage.qml", []),
                  ("clock-x1", "ClockTest.qml", ["--speed=1", "--output=" + str(output / "clock-x1")]),
                  ("clock-x10", "ClockTest.qml", ["--speed=10", "--output=" + str(output / "clock-x10")]),
                  ("motion", "MotionRender.qml", ["--frames=181", "--step=160", "--output=" + str(output / "motion-fixed")])]
    results = {}
    for name, qml, options in cases:
        print("Running", name, flush=True)
        command = [qt_tool("qml"), str(runtime / "weather-tests" / qml)]
        if options:
            command += ["--", *options]
        started = time.monotonic()
        result = subprocess.run(command, env=environment, capture_output=True, text=True, timeout=170)
        (output / (name + ".log")).write_text(result.stdout + result.stderr)
        results[name] = {"returncode": result.returncode, "wallSeconds": round(time.monotonic() - started, 2)}
        (output / "test-processes.json").write_text(json.dumps(results, indent=2) + "\n")
        if result.returncode:
            raise SystemExit(f"Native check failed: {name}; inspect the local build/test-output log")
    if args.full:
        subprocess.run([os.sys.executable, str(ROOT / "scripts/verify_native.py")], check=True)
    print("Native checks passed")


if __name__ == "__main__":
    main()
