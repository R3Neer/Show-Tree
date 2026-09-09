"""Exercise Show-Tree in a real Nushell REPL through a pseudo-terminal."""
from __future__ import annotations

from pathlib import Path
import re
import shutil
import tempfile

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


def submit(child: pexpect.spawn, command: str) -> None:
    """Submit one line as a terminal Enter key, not as a Unix LF."""
    child.send(command)
    child.send("\r")


def run_marked(child: pexpect.spawn, command: str, marker: str) -> str:
    """Execute one REPL line and return only output produced after its marker.

    Reedline redraws the command while it is being typed. The marker is split in
    the submitted source so it can occur only after execution, then all repaint
    noise before that marker is discarded. Assertions therefore inspect rendered
    command output rather than the editor's copy of paths and arguments.
    """
    midpoint = len(marker) // 2
    left = marker[:midpoint]
    right = marker[midpoint:]
    submit(child, f"print ('{left}' + '{right}'); {command}")
    expect_while_answering_cpr(child, marker)
    return read_to_prompt(child)


def assert_tree(output: str, context: str) -> None:
    if "SHOW-TREE" not in output:
        raise AssertionError(f"{context} did not render the R3CLI tree:\n{output}")
    if "╭" in output:
        raise AssertionError(f"{context} rendered a Nushell table instead of the R3CLI tree:\n{output}")


def main() -> None:
    fixture = Path(tempfile.mkdtemp(prefix="show-tree-repl-"))
    alpha = fixture / "alpha"
    beta = fixture / "beta"
    empty = fixture / "empty"
    snapshot = fixture / "snapshot.showtree"
    alpha.mkdir()
    beta.mkdir()
    empty.mkdir()
    (fixture / "root.txt").write_text("abc", encoding="utf-8")
    (fixture / ".hidden.txt").write_text("hidden", encoding="utf-8")
    (alpha / "nested.txt").write_text("hello", encoding="utf-8")
    (beta / "beta.txt").write_text("a much larger child", encoding="utf-8")

    fixture_nu = fixture.as_posix().replace("'", "''")
    snapshot_nu = snapshot.as_posix().replace("'", "''")

    child = pexpect.spawn(
        "nu",
        ["--config", str(CONFIG)],
        cwd=str(ROOT.parent),
        encoding="utf-8",
        timeout=25,
        dimensions=(60, 180),
    )

    try:
        read_to_prompt(child)

        rendered = run_marked(
            child,
            f"show-tree '{fixture_nu}' -d 2",
            "__SHOW_TREE_DIRECT__",
        )
        assert_tree(rendered, "A direct Show-Tree call")
        if "Hidden entries are omitted" not in rendered:
            raise AssertionError(f"Default interactive tree did not show the hidden-entry reminder:\n{rendered}")
        if ".hidden.txt" in rendered:
            raise AssertionError(f"Default interactive tree exposed a hidden entry:\n{rendered}")

        all_rendered = run_marked(
            child,
            f"show-tree '{fixture_nu}' -d 2 --all",
            "__SHOW_TREE_ALL__",
        )
        assert_tree(all_rendered, "A Show-Tree --all call")
        if ".hidden.txt" not in all_rendered:
            raise AssertionError(f"--all did not render the hidden entry:\n{all_rendered}")
        if "Hidden entries are omitted" in all_rendered:
            raise AssertionError(f"--all still showed the hidden-entry reminder:\n{all_rendered}")

        repeated = run_marked(child, "$ans.last", "__SHOW_TREE_LAST__")
        assert_tree(repeated, "$ans.last")

        # Filtering keeps the tree view. Removing the original root promotes alpha
        # to a visual root, while nested.txt remains its child.
        filtered = run_marked(
            child,
            f"show-tree '{fixture_nu}' -d 2 | where name in [alpha nested.txt]",
            "__SHOW_TREE_FILTERED__",
        )
        assert_tree(filtered, "A filtered Show-Tree result")
        if alpha.as_posix() not in filtered or "nested.txt" not in filtered:
            raise AssertionError(f"Filtered tree lost retained nodes:\n{filtered}")
        if filtered.find(alpha.as_posix()) > filtered.find("nested.txt"):
            raise AssertionError(f"Filtered child appeared before its promoted parent:\n{filtered}")
        if "Hidden entries are omitted" not in filtered:
            raise AssertionError(f"Filtered tree lost the hidden-entry reminder metadata:\n{filtered}")

        filtered_last = run_marked(child, "$ans.last", "__SHOW_TREE_FILTERED_LAST__")
        assert_tree(filtered_last, "$ans.last after filtering")

        # Global sort order is advisory for hierarchy: parents must still precede
        # descendants. When the original root remains visible, child directories
        # are displayed by basename, not by full path.
        sorted_tree = run_marked(
            child,
            f"show-tree '{fixture_nu}' -d 2 | sort-by size",
            "__SHOW_TREE_SORTED__",
        )
        assert_tree(sorted_tree, "A size-sorted Show-Tree result")
        for parent_label, descendant in (("alpha", "nested.txt"), ("beta", "beta.txt")):
            if parent_label not in sorted_tree or descendant not in sorted_tree:
                raise AssertionError(
                    f"Sorted tree lost {parent_label!r} or {descendant!r}:\n{sorted_tree}"
                )
            if sorted_tree.find(parent_label) > sorted_tree.find(descendant):
                raise AssertionError(
                    f"Sorted descendant appeared before parent {parent_label!r}:\n{sorted_tree}"
                )

        sibling_sort = run_marked(
            child,
            f"show-tree '{fixture_nu}' -d 2 | where type == 'dir' | sort-by size --reverse",
            "__SHOW_TREE_SIBLINGS__",
        )
        assert_tree(sibling_sort, "A sibling-sorted Show-Tree result")
        if sibling_sort.find("beta") > sibling_sort.find("alpha"):
            raise AssertionError(f"Sibling sort order was not preserved under the root:\n{sibling_sort}")

        short_tree = run_marked(
            child,
            f"show-tree '{fixture_nu}' -d 2 --short",
            "__SHOW_TREE_SHORT__",
        )
        assert_tree(short_tree, "A Show-Tree --short call")
        if "root.txt" in short_tree or "nested.txt" in short_tree or "beta.txt" in short_tree:
            raise AssertionError(f"--short rendered file rows:\n{short_tree}")
        if "alpha" not in short_tree or "beta" not in short_tree:
            raise AssertionError(f"--short lost directory rows:\n{short_tree}")

        # Saving as .showtree persists native rows rather than the human drawing.
        # Reopening the file in a fresh REPL expression restores metadata strongly
        # enough for the normal display hook to render it immediately as a tree.
        saved = run_marked(
            child,
            f"show-tree '{fixture_nu}' -d 2 | save --force '{snapshot_nu}'; print 'saved'",
            "__SHOW_TREE_SNAPSHOT_SAVE__",
        )
        if "saved" not in saved:
            raise AssertionError(f"Saving .showtree did not complete:\n{saved}")

        reopened = run_marked(
            child,
            f"open '{snapshot_nu}'",
            "__SHOW_TREE_SNAPSHOT_OPEN__",
        )
        assert_tree(reopened, "An opened .showtree snapshot")
        if "nested.txt" not in reopened or "beta.txt" not in reopened:
            raise AssertionError(f"Opened .showtree snapshot lost descendants:\n{reopened}")

        reopened_filtered = run_marked(
            child,
            f"open '{snapshot_nu}' | where name in [alpha nested.txt]",
            "__SHOW_TREE_SNAPSHOT_FILTERED__",
        )
        assert_tree(reopened_filtered, "A filtered opened .showtree snapshot")
        if alpha.as_posix() not in reopened_filtered or "nested.txt" not in reopened_filtered:
            raise AssertionError(f"Filtered .showtree snapshot lost retained nodes:\n{reopened_filtered}")
        if "beta" in reopened_filtered:
            raise AssertionError(f"Filtered .showtree snapshot reintroduced a removed node:\n{reopened_filtered}")

        # Explicit table is the intentional escape hatch from the tree renderer.
        explicit_table = run_marked(
            child,
            f"show-tree '{fixture_nu}' -d 2 | table",
            "__SHOW_TREE_TABLE__",
        )
        if "╭" not in explicit_table:
            raise AssertionError(
                "Explicit table output did not use Nushell's normal table renderer. Full REPL output:\n"
                + explicit_table
            )
        for expected in ("name", "type", "size", "children", "path"):
            if expected not in explicit_table:
                raise AssertionError(
                    f"Explicit table output is missing the {expected!r} column:\n{explicit_table}"
                )
        if "[table" in explicit_table:
            raise AssertionError(
                "Explicit table output collapsed descendants into nested table placeholders."
            )

        # Removing required semantic columns makes the value non-tree-representable,
        # so the normal Nu display hook takes over automatically.
        reduced = run_marked(
            child,
            f"show-tree '{fixture_nu}' -d 2 | select name size",
            "__SHOW_TREE_REDUCED__",
        )
        if "SHOW-TREE" in reduced or "╭" not in reduced:
            raise AssertionError(
                "A non-representable transformed value should fall back to Nushell's table display:\n"
                + reduced
            )

        normal_output = run_marked(child, "[1 2]", "__NORMAL_TABLE__")
        if "╭" not in normal_output:
            raise AssertionError(
                "Show-Tree's display hook did not preserve the previous/default table renderer."
            )

        submit(child, "exit")
        child.expect(pexpect.EOF)
    finally:
        if child.isalive():
            child.close(force=True)
        shutil.rmtree(fixture, ignore_errors=True)


if __name__ == "__main__":
    main()
