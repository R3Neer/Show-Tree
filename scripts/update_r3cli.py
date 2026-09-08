"""Vendor an exact clean R3CLI revision for Show-Tree.

Development only. The resulting Show-Tree checkout is self-contained at install
and runtime; Python and a separate R3CLI checkout are not required by users.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
VENDOR = ROOT / "vendor" / "R3CLI"
DEPENDENCIES = ROOT / "dependencies.json"


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest().upper()


def files_manifest(root: Path) -> dict[str, str]:
    return {
        path.relative_to(root).as_posix(): sha256(path)
        for path in sorted(root.rglob("*"))
        if path.is_file()
    }


def update(source: Path, allow_dirty: bool = False) -> None:
    def git(*args: str) -> str:
        return subprocess.check_output(
            ["git", "-C", str(source), *args], text=True
        ).strip()

    if git("status", "--porcelain") and not allow_dirty:
        raise SystemExit("Commit R3CLI first; vendoring requires a clean revision.")

    revision = git("rev-parse", "HEAD")
    powershell = VENDOR / "powershell"
    nushell = VENDOR / "nushell" / "r3cli"

    # Clean only generated dependency destinations. Broad repository cleanup is
    # deliberately avoided so unrelated working files cannot be removed.
    for destination in (powershell, nushell):
        if destination.exists():
            shutil.rmtree(destination)

    subprocess.run(
        [
            sys.executable,
            str(source / "scripts" / "build_powershell.py"),
            "--output",
            str(powershell),
        ],
        check=True,
    )
    subprocess.run(
        [
            sys.executable,
            str(source / "scripts" / "build_nushell.py"),
            "--output",
            str(nushell),
        ],
        check=True,
    )

    manifest_text = (powershell / "R3CLI.psd1").read_text(encoding="utf-8")
    match = re.search(r"ModuleVersion\s*=\s*'([^']+)'", manifest_text)
    if match is None:
        raise SystemExit("Could not read the R3CLI version from R3CLI.psd1.")

    dependency = {
        "R3CLI": {
            "version": match.group(1),
            "revision": revision,
            "source": "https://github.com/R3Neer/R3CLI",
            "powershell": {"files": files_manifest(powershell)},
            "nushell": {"files": files_manifest(nushell)},
        }
    }
    DEPENDENCIES.write_text(
        json.dumps(dependency, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
        newline="\n",
    )

    print(
        json.dumps(
            {
                "revision": revision,
                "version": match.group(1),
                "powershell_files": len(dependency["R3CLI"]["powershell"]["files"]),
                "nushell_files": len(dependency["R3CLI"]["nushell"]["files"]),
            }
        )
    )


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument(
        "--allow-dirty",
        action="store_true",
        help="Local iteration only; regenerate from a clean commit before delivery.",
    )
    args = parser.parse_args()
    update(args.source.resolve(), args.allow_dirty)
