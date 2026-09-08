"""Exercise Show-Tree in a real Nushell REPL through a pseudo-terminal."""
from __future__ import annotations

from pathlib import Path
import re

import pexpect

ROOT = Path(__file__).resolve().parents[1]
CONFIG = ROOT / "tests" / "Nushell.ReplConfig.nu"

PROMPT = re.compile(r">\s")


def read_to_prompt(child: pexpect.spawn) -> str:
    child.expect(PROMPT)
    return child.before


def main() -> None:
    child = pexpect.spawn(
        "nu",
        ["--config", str(CONFIG)],
        cwd=str(ROOT.parent),
        encoding="utf-8",
        timeout=20,
        dimensions=(40, 140),
    )

    try:
        read_to_prompt(child)

        child.sendline("show-tree Show-Tree -d 0")
        rendered = read_to_prompt(child)
        if "SHOW-TREE" not in rendered:
            raise AssertionError(f"R3CLI tree was not rendered:\n{rendered}")
        if "╭" in rendered:
            raise AssertionError(
                "The native Show-Tree result was displayed a second time as a Nushell table."
            )

        child.sendline("$ans.last.0.type")
        ans_output = read_to_prompt(child)
        if not re.search(r"\bdir\b", ans_output):
            raise AssertionError(f"$ans.last did not retain the native result:\n{ans_output}")

        child.sendline("[1 2]")
        normal_output = read_to_prompt(child)
        if "╭" not in normal_output:
            raise AssertionError(
                "Show-Tree's display hook did not preserve the previous/default table renderer."
            )

        child.sendline("exit")
        child.expect(pexpect.EOF)
    finally:
        if child.isalive():
            child.close(force=True)


if __name__ == "__main__":
    main()
