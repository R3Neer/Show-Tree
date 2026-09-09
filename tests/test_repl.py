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


def run_and_collect(child: pexpect.spawn, command: str, target: str | re.Pattern[str]) -> str:
    child.sendline(command)
    output = expect_while_answering_cpr(child, target)
    output += read_to_prompt(child)
    return output


def main() -> None:
    child = pexpect.spawn(
        "nu",
        ["--config", str(CONFIG)],
        cwd=str(ROOT.parent),
        encoding="utf-8",
        timeout=25,
        dimensions=(50, 160),
    )

    try:
        read_to_prompt(child)

        rendered = run_and_collect(child, "show-tree Show-Tree -d 1", "SHOW-TREE")
        if "╭" in rendered:
            raise AssertionError(
                "A direct Show-Tree call should render the R3CLI tree, not the native table."
            )

        repeated = run_and_collect(child, "$ans.last", "SHOW-TREE")
        if "╭" in repeated:
            raise AssertionError(
                "$ans.last should redisplay the Show-Tree value as the same R3CLI tree."
            )

        explicit_table = run_and_collect(child, "$ans.last | table", "╭")
        for expected in ("path", "type", "size"):
            if expected not in explicit_table:
                raise AssertionError(
                    f"Explicit table output is missing the {expected!r} column:\n{explicit_table}"
                )
        for redundant_or_presentation_only in ("name", "tree", "depth"):
            if redundant_or_presentation_only in explicit_table:
                raise AssertionError(
                    "Explicit table output leaked redundant or presentation-only "
                    f"{redundant_or_presentation_only!r} data:\n{explicit_table}"
                )
        if "[table" in explicit_table:
            raise AssertionError(
                "Explicit table output collapsed descendants into nested table placeholders."
            )

        normal_output = run_and_collect(child, "[1 2]", "╭")
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
