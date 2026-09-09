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


def run_marked(child: pexpect.spawn, command: str, marker: str) -> str:
    """Execute one REPL line and collect everything after an execution marker.

    Reedline can repaint the prompt while Enter is being handled, so waiting for
    the next prompt alone can race with execution. A marker printed by the command
    itself gives us an unambiguous point after evaluation has actually started and,
    unlike waiting for the expected UI text, also exposes parse/runtime errors.
    """
    child.sendline(f"print '{marker}'; {command}")
    output = expect_while_answering_cpr(child, marker)
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

        rendered = run_marked(child, "show-tree Show-Tree -d 1", "__SHOW_TREE_DIRECT__")
        if "SHOW-TREE" not in rendered:
            raise AssertionError(
                "A direct Show-Tree call did not render the R3CLI tree. Full REPL output:\n"
                + rendered
            )
        if "╭" in rendered:
            raise AssertionError(
                "A direct Show-Tree call should render the R3CLI tree, not the native table."
            )

        repeated = run_marked(child, "$ans.last", "__SHOW_TREE_LAST__")
        if "SHOW-TREE" not in repeated:
            raise AssertionError(
                "$ans.last did not redisplay the Show-Tree value as the R3CLI tree. Full REPL output:\n"
                + repeated
            )
        if "╭" in repeated:
            raise AssertionError(
                "$ans.last should redisplay the Show-Tree value as the same R3CLI tree."
            )

        explicit_table = run_marked(child, "$ans.last | table", "__SHOW_TREE_TABLE__")
        if "╭" not in explicit_table:
            raise AssertionError(
                "Explicit table output did not use Nushell's normal table renderer. Full REPL output:\n"
                + explicit_table
            )
        for expected in ("name", "type", "size", "path"):
            if expected not in explicit_table:
                raise AssertionError(
                    f"Explicit table output is missing the {expected!r} column:\n{explicit_table}"
                )
        for presentation_only in ("tree", "depth"):
            if presentation_only in explicit_table:
                raise AssertionError(
                    f"Explicit table output leaked presentation-only {presentation_only!r} data:\n{explicit_table}"
                )
        if "[table" in explicit_table:
            raise AssertionError(
                "Explicit table output collapsed descendants into nested table placeholders."
            )

        normal_output = run_marked(child, "[1 2]", "__NORMAL_TABLE__")
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
