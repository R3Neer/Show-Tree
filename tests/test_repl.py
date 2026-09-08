"""Exercise Show-Tree in a real Nushell REPL through a pseudo-terminal."""
from __future__ import annotations

from pathlib import Path
import re

import pexpect

ROOT = Path(__file__).resolve().parents[1]
CONFIG = ROOT / "tests" / "Nushell.ReplConfig.nu"

PROMPT = re.escape("show-tree-test> ")
CURSOR_POSITION_QUERY = re.escape("\x1b[6n")
CURSOR_POSITION_REPLY = "\x1b[1;1R"


def expect_while_answering_cpr(child: pexpect.spawn, target: str | re.Pattern[str]) -> str:
    """Read through Reedline terminal queries until target is observed."""
    chunks: list[str] = []
    while True:
        match = child.expect([target, CURSOR_POSITION_QUERY])
        chunks.append(child.before)
        if match == 0:
            chunks.append(child.after)
            return "".join(chunks)
        child.send(CURSOR_POSITION_REPLY)


def read_to_prompt(child: pexpect.spawn) -> str:
    return expect_while_answering_cpr(child, PROMPT)


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

        # Reedline may repaint the prompt while accepting Enter. Synchronize on
        # the command's own output first, then consume through the next prompt.
        child.sendline("show-tree Show-Tree -d 0")
        rendered = expect_while_answering_cpr(child, "SHOW-TREE")
        rendered += read_to_prompt(child)
        if "╭" in rendered:
            raise AssertionError(
                "The native Show-Tree result was displayed a second time as a Nushell table."
            )

        child.sendline("$ans.last.0.type")
        ans_output = expect_while_answering_cpr(child, re.compile(r"\bdir\b"))
        ans_output += read_to_prompt(child)
        if not re.search(r"\bdir\b", ans_output):
            raise AssertionError(f"$ans.last did not retain the native result:\n{ans_output}")

        child.sendline("[1 2]")
        normal_output = expect_while_answering_cpr(child, "╭")
        normal_output += read_to_prompt(child)
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
