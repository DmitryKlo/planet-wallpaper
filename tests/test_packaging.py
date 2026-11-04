from __future__ import annotations

import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]


def module(name):
    spec = importlib.util.spec_from_file_location(name, ROOT / "scripts" / (name + ".py"))
    result = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(result)
    return result


class PackagingTests(unittest.TestCase):
    def test_runtime_assets_match_manifest(self):
        self.assertEqual(len(module("build").verify_assets()), 4)

    def test_install_preserves_settings_and_creates_backup(self):
        installer = module("install")
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            runtime = root / "build"
            runtime.mkdir()
            (runtime / ".planet-wallpaper-build").write_text("generated\n")
            (runtime / "shell.qml").write_text("new source\n")
            (runtime / "settings.json").write_text('{"view":"horizon"}\n')
            target = root / "config/quickshell/planet-wallpaper"
            target.mkdir(parents=True)
            (target / "shell.qml").write_text("old source\n")
            retained = '{"view":"globe","weatherEnabled":false}\n'
            (target / "settings.json").write_text(retained)
            result = installer.install(root / "config", root / "data", root / "bin",
                                       runtime=runtime, qs_binary="/usr/bin/qs", no_systemd=True)
            self.assertEqual((target / "settings.json").read_text(), retained)
            self.assertEqual((target / "shell.qml").read_text(), "new source\n")
            self.assertEqual((Path(result["backup"]) / "runtime/shell.qml").read_text(), "old source\n")
            self.assertIn(" -p ", Path(result["unit"]).read_text())
            self.assertTrue(Path(result["wrapper"]).stat().st_mode & 0o111)

    def test_invalid_settings_leave_installation_untouched(self):
        installer = module("install")
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            runtime = root / "build"
            runtime.mkdir()
            (runtime / ".planet-wallpaper-build").write_text("generated\n")
            target = root / "config/quickshell/planet-wallpaper"
            target.mkdir(parents=True)
            (target / "settings.json").write_text("invalid JSON")
            (target / "shell.qml").write_text("keep this")
            with self.assertRaises(json.JSONDecodeError):
                installer.install(root / "config", root / "data", root / "bin", runtime=runtime,
                                  qs_binary="/usr/bin/qs", no_systemd=True)
            self.assertEqual((target / "shell.qml").read_text(), "keep this")

    def test_unmarked_output_is_not_deleted(self):
        builder = module("build")
        with tempfile.TemporaryDirectory() as directory:
            with patch.object(builder, "qt_tool", return_value="qsb"):
                with self.assertRaisesRegex(RuntimeError, "unmarked"):
                    builder.build(Path(directory))

    def test_audit_redacts_known_credentials(self):
        auditor = module("audit")
        sample = b"gh" + b"p_" + b"a" * 36
        findings = auditor.inspect_file("sample.txt", sample, [sample])
        self.assertTrue(findings)
        self.assertNotIn(sample.decode(), json.dumps(findings))
        self.assertIn("known-local-credential", {finding["rule"] for finding in findings})

    def test_audit_rejects_private_paths_and_settings(self):
        auditor = module("audit")
        sample = b"/home/" + b"account/private-file"
        self.assertTrue(auditor.inspect_file("sample.txt", sample, []))
        self.assertTrue(auditor.inspect_file("settings.json", b"{}", []))


if __name__ == "__main__":
    unittest.main()
