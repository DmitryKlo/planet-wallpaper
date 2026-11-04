"""Check native readbacks and the fixed-geography cloud-motion sequence."""

import json
from pathlib import Path

import numpy as np
from PIL import Image

PROJECT = Path(__file__).resolve().parents[1]
OUTPUT = PROJECT / "build/test-output"


def pixels(path: Path) -> np.ndarray:
    return np.asarray(Image.open(path).convert("RGB")).astype(np.int16)


def changed(a: np.ndarray, b: np.ndarray) -> list[int]:
    return np.count_nonzero(a != b, axis=(0, 1)).tolist()


def main() -> None:
    processes = json.loads((OUTPUT / "test-processes.json").read_text())
    assert all(v["returncode"] == 0 for v in processes.values())
    initial = pixels(OUTPUT / "model/step-1.png")
    later = pixels(OUTPUT / "model/step-361.png")
    channels = changed(initial[:, :768], later[:, :768]) + changed(
        initial[:, 768:1536], later[:, 768:1536]
    )
    assert all(v > 0 for v in channels), channels
    assert np.array_equal(initial, pixels(OUTPUT / "model/reset.png"))

    coverage = {}
    for step in (1, 361, 2161):
        coverage[step] = {}
        for mode in ("globe", "horizon"):
            paths = sorted((OUTPUT / "late-coverage").glob(f"step-{step}-{mode}-*.png"))
            assert len(paths) == 24
            values = []
            for path in paths:
                frame = pixels(path)
                surface = frame[:, :, 1] > 250
                values.append(float(np.mean(frame[:, :, 0][surface] > 12) * 100))
            assert min(values) > 0 and max(values) < 30, values
            coverage[step][mode] = {
                "frames": len(values), "min_percent": min(values), "max_percent": max(values)
            }

    dry = pixels(OUTPUT / "condensate-test/no-condensate.png")
    wet = pixels(OUTPUT / "condensate-test/with-condensate.png")
    removed = pixels(OUTPUT / "condensate-test/condensate-removed.png")
    assert dry.max() == 0 and removed.max() == 0
    assert all(wet[:, start:start + 768, channel].max() > 10
               for start in (0, 768) for channel in range(3))
    held = pixels(OUTPUT / "toggle/disabled-initial.png")
    assert np.array_equal(held, pixels(OUTPUT / "toggle/disabled-after-day.png"))
    assert np.array_equal(held, pixels(OUTPUT / "toggle/enabled-before-step.png"))
    assert not np.array_equal(held, pixels(OUTPUT / "toggle/enabled-after-step.png"))

    clocks = {}
    for speed in (1, 10):
        log = (OUTPUT / f"clock-x{speed}.log").read_text()
        marker = "CLOCK_RESULT "
        data = json.loads(next(line.split(marker, 1)[1] for line in log.splitlines() if marker in line))
        final = data["final"]
        assert abs(final["simulatedTime"] - 2880 * speed) < 40
        assert final["lastStepSeconds"] <= final["maximumStepSeconds"]
        assert final["lagSeconds"] < 40.01
        assert data["maximumLag"] < 1000
        start = pixels(OUTPUT / f"clock-x{speed}/second-0.png")
        third = pixels(OUTPUT / f"clock-x{speed}/second-3.png")
        data["three_second_cloud_mean_abs_delta_255"] = float(
            np.abs(start[:, :1536] - third[:, :1536]).mean()
        )
        clocks[speed] = data
    assert clocks[10]["three_second_cloud_mean_abs_delta_255"] > 2 * clocks[1][
        "three_second_cloud_mean_abs_delta_255"
    ]

    start = pixels(OUTPUT / "motion-fixed/frame-0000.png")
    third = pixels(OUTPUT / "motion-fixed/frame-0045.png")
    y, x = np.indices(start.shape[:2])
    radius = .435 * start.shape[0]
    distance = np.hypot(x - .520 * start.shape[1], y - .530 * start.shape[0])
    delta = np.max(np.abs(start - third), axis=2)
    visible_change = float(np.mean(delta[distance < .97 * radius] > 4) * 100)
    assert visible_change > 3, visible_change
    assert delta[distance > 1.01 * radius].max() == 0
    report = {
        "coverage_threshold_alpha": "12/255",
        "coverage": coverage,
        "all_six_cloud_fields_evolve": channels,
        "reset_reproducible": True,
        "zero_condensate_zero_clouds": True,
        "weather_off_preserves_fields_and_evolution_clock": True,
        "clock_tests": clocks,
        "fixed_geography_motion": {
            "speed": 10, "fps": 15, "model_seconds_per_frame": 160,
            "surface_percent_changed_over_4_levels_in_3_seconds": visible_change,
            "sky_pixel_max_delta": 0,
        },
        "test_processes": processes,
    }
    (OUTPUT / "report.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps({"passed": True, "six_field_changes": channels,
                      "visible_cloud_change_percent_in_3_seconds": visible_change}, indent=2))


if __name__ == "__main__":
    main()
