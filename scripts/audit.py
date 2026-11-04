#!/usr/bin/env python3
"""Local-only credential and privacy audit. Findings never contain secret values."""

from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import re
import struct
import subprocess

ROOT = Path(__file__).resolve().parents[1]
SKIP = {".git", ".publish", "build", "dist", "backups", ".venv", "__pycache__"}
FORBIDDEN_NAMES = {".env", ".git-credentials", ".netrc", "hosts.yml", "settings.json",
                   "id_rsa", "id_ed25519", "credentials.json", "secrets.json"}
FORBIDDEN_SUFFIXES = {".key", ".pem", ".p12", ".pfx", ".keystore"}
PATTERNS = {
    "github-token": rb"\bgh[pousr]_[A-Za-z0-9_]{30,}\b|\bgithub_pat_[A-Za-z0-9_]{35,}\b",
    "cloud-access-key": rb"\b(?:AKIA|ASIA)[A-Z0-9]{16}\b",
    "private-key": rb"-----BEGIN (?:[A-Z0-9 ]+ )?PRIVATE KEY-----",
    "google-api-key": rb"\bAIza[0-9A-Za-z_-]{35}\b",
    "service-token": rb"\bxox[baprs]-[0-9A-Za-z-]{20,}\b|\bsk_(?:live|test)_[0-9A-Za-z]{20,}\b",
    "bearer-value": rb"(?i)\bBearer\s+[A-Za-z0-9._~+/-]{20,}",
    "credential-in-url": rb"(?i)https?://[^\s/:]+:[^\s/@]+@",
    "personal-home-path": rb"(?:/home/|/Users/)[a-zA-Z0-9_.-]+/",
}
COMPILED = {name: re.compile(pattern) for name, pattern in PATTERNS.items()}
ASSIGNMENT = re.compile(
    rb"(?i)(?:[\"']?(?:api[_-]?key|access[_-]?token|auth[_-]?token|client[_-]?secret|"
    rb"password|passwd|secret|token)[\"']?)\s*[:=]\s*[\"']([^\"'\r\n]{8,})[\"']"
)


def known_values(include_github: bool = False) -> list[bytes]:
    values = [value.encode() for name, value in os.environ.items()
              if re.search(r"TOKEN|PASSWORD|PASSWD|SECRET|API_KEY|PRIVATE_KEY", name, re.I)
              and len(value) >= 8]
    if include_github:
        result = subprocess.run(["gh", "auth", "token"], capture_output=True, check=False)
        if result.returncode or len(result.stdout.strip()) < 20:
            raise RuntimeError("Cannot read the local GitHub credential for exact-match verification")
        values.append(result.stdout.strip())
    return values


def inspect_bytes(data: bytes, known: list[bytes]) -> list[tuple[str, int]]:
    findings = []
    for name, pattern in COMPILED.items():
        for match in pattern.finditer(data):
            findings.append((name, data.count(b"\n", 0, match.start()) + 1))
    for value in known:
        if value and value in data:
            findings.append(("known-local-credential", data.count(b"\n", 0, data.index(value)) + 1))
    for match in ASSIGNMENT.finditer(data):
        value = match.group(1).lower()
        if any(marker in value for marker in (b"example", b"placeholder", b"your_", b"changeme", b"dummy")):
            continue
        findings.append(("literal-credential-assignment", data.count(b"\n", 0, match.start()) + 1))
    if data.startswith(b"\x89PNG\r\n\x1a\n"):
        offset = 8
        while offset + 12 <= len(data):
            length = struct.unpack(">I", data[offset:offset + 4])[0]
            kind = data[offset + 4:offset + 8]
            if kind in {b"tEXt", b"zTXt", b"iTXt", b"eXIf"}:
                findings.append(("image-text-or-exif-metadata", 0))
            offset += length + 12
    return findings


def safe_name(name: str, known: list[bytes]) -> str:
    value = name.encode()
    for pattern in COMPILED.values():
        value = pattern.sub(b"[REDACTED]", value)
    for secret in known:
        value = value.replace(secret, b"[REDACTED]")
    return value.decode(errors="replace")


def inspect_file(name: str, data: bytes, known: list[bytes]) -> list[dict]:
    path = Path(name)
    found = inspect_bytes(data, known)
    if path.name in FORBIDDEN_NAMES or path.name.startswith(".env.") or path.suffix in FORBIDDEN_SUFFIXES:
        found.append(("credential-or-local-settings-file", 0))
    return [{"path": safe_name(name, known), "rule": rule, "line": line} for rule, line in sorted(set(found))]


def audit(root: Path, *, history: bool = False, include_github: bool = False) -> dict:
    known = known_values(include_github)
    findings = []
    checked = 0
    for directory, directories, files in os.walk(root, followlinks=False):
        directories[:] = [name for name in directories if name not in SKIP]
        for name in files:
            path = Path(directory) / name
            relative = path.relative_to(root).as_posix()
            if path.is_symlink():
                findings.append({"path": safe_name(relative, known), "rule": "symlink-not-allowed", "line": 0})
                continue
            findings.extend(inspect_file(relative, path.read_bytes(), known))
            checked += 1
    objects = 0
    if history and (root / ".git").exists():
        entries = subprocess.run(["git", "-C", str(root), "rev-list", "--objects", "--all"],
                                 capture_output=True, text=True, check=True).stdout.splitlines()
        names = dict(line.split(" ", 1) if " " in line else (line, "commit-metadata") for line in entries)
        if names:
            types = subprocess.run(["git", "-C", str(root), "cat-file", "--batch-check"],
                                   input="\n".join(names) + "\n", capture_output=True, text=True, check=True)
            for line in types.stdout.splitlines():
                sha, kind, *_ = line.split()
                if kind not in {"blob", "commit"}:
                    continue
                data = subprocess.run(["git", "-C", str(root), "cat-file", kind, sha],
                                      capture_output=True, check=True).stdout
                findings.extend(inspect_file("history/" + names[sha], data, known))
                objects += 1
    return {"passed": not findings, "files_checked": checked, "history_objects_checked": objects,
            "known_credential_values_checked": len(known), "findings": findings}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=ROOT)
    parser.add_argument("--history", action="store_true")
    parser.add_argument("--check-gh-token", action="store_true")
    parser.add_argument("--report", type=Path)
    args = parser.parse_args()
    report = audit(args.root.resolve(), history=args.history, include_github=args.check_gh_token)
    payload = json.dumps(report, indent=2) + "\n"
    if args.report:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(payload)
    print(payload, end="")
    raise SystemExit(0 if report["passed"] else 1)


if __name__ == "__main__":
    main()
