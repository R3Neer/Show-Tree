# Show-Tree

[![Test](https://github.com/R3Neer/Show-Tree/actions/workflows/test.yml/badge.svg)](https://github.com/R3Neer/Show-Tree/actions/workflows/test.yml)

A size-aware filesystem tree for PowerShell and Nushell, with an R3CLI terminal view for humans and native Nushell rows for pipelines.

Show-Tree is designed around one rule: **presentation and data are the same result, not two unrelated modes**.

```text
interactive REPL                pipeline / explicit table
       │                                  │
       ▼                                  ▼
  R3CLI tree                     native Nushell rows
       │                                  │
       └──────── same traversal ───────────┘
```

R3CLI is bundled as a verified private dependency. Installing Show-Tree does not require a separate R3CLI checkout or Python runtime.

## Quick start

In Nushell:

```nu
show-tree D:/Tools -d 2
```

A direct REPL result is rendered as a tree:

```text
SHOW-TREE
D:\Tools [Folder] (...)
├── ModpackTools [Folder] (...)
├── R3CLI [Folder] (...)
└── Show-Tree [Folder] (...)

Total size       ...
```

The value behind that view is still native Nushell data. Ask for a table explicitly and the same traversal becomes a normal flat table:

```nu
show-tree D:/Tools -d 2 | table
```

```text
╭───┬──────────────┬──────┬──────────┬─────────────────────────╮
│ # │     name     │ type │   size   │          path           │
├───┼──────────────┼──────┼──────────┼─────────────────────────┤
│ 0 │ Tools        │ dir  │ ...      │ D:\Tools                │
│ 1 │ ModpackTools │ dir  │ ...      │ D:\Tools\ModpackTools   │
│ 2 │ R3CLI        │ dir  │ ...      │ D:\Tools\R3CLI          │
│ 3 │ Show-Tree    │ dir  │ ...      │ D:\Tools\Show-Tree      │
╰───┴──────────────┴──────┴──────────┴─────────────────────────╯
```

That means ordinary Nu operations work without a JSON flag or text parsing:

```nu
show-tree D:/Tools -d 2
| where type == dir
| sort-by size --reverse

show-tree D:/Tools -d 3 -l
| where size > 10mb
| select name size path

show-tree D:/Tools -d 3
| to json
```

## `$ans.last` and interactive display

A direct call stores the same native table in Nushell's last-result machinery when `max_last_result_size` allows it:

```nu
show-tree D:/Tools -d 2
$ans.last
```

Both lines render as the Show-Tree tree. The display integration recognizes metadata attached to the unchanged result and redraws the R3CLI view instead of Nushell's automatic table.

To inspect the native rows explicitly:

```nu
$ans.last | table
```

or keep a stable reference before experimenting:

```nu
let tree = $ans.last
$tree | table
$tree | where type == dir
```

This matters because `table` itself produces rendered text. After running `$ans.last | table`, Nushell may make that rendered result the new last result. Saving the native value to a variable avoids that normal REPL behaviour.

If a marked Show-Tree value is filtered, sorted, selected or otherwise changed, the display integration does **not** redraw a stale hierarchy. The transformed value falls back to Nushell's normal display path.

## Nushell data contract

The public result is deliberately flat and compact:

```nu
{
    name: string
    type: 'dir' | 'file'
    size: filesize
    path: string
}
```

One visible filesystem node equals one row. There are no nested `children` tables to collapse into placeholders such as `[table 36 rows]`.

The branch glyphs and depth information required for the interactive R3CLI tree are presentation metadata, not public columns. They are therefore absent from `table`, JSON, NUON and other machine-readable output.

Without `--long`, file rows are omitted from the returned table, but file sizes still contribute to directory totals.

## Options

| Behaviour | PowerShell | Nushell |
| --- | --- | --- |
| Starting paths | positional / `Path` | positional |
| Dereference links for size metadata | `-Dereference`, `-r` | `--deref`, `-r` |
| Include file rows | `-Long`, `-l` | `--long`, `-l` |
| Exclude matching file paths | `-Exclude`, `-x` | `--exclude`, `-x` |
| Maximum traversal depth | `-MaxDepth`, `-d` | `--max-depth`, `-d` |
| Minimum included file size | `-MinSize`, `-m` | `--min-size`, `-m` |
| Include dot-prefixed entries | `-All`, `-a` | `--all`, `-a` |
| Hide folders with no included files | `-HideEmptyFolders`, `-e` | `--hide-empty-folders`, `-e` |
| Help | `-Help`, `-h` | `--help`, `-h` |

Examples:

```nu
show-tree
show-tree D:/Projects -d 2
show-tree D:/Projects -d 3 -l
show-tree D:/Projects -m 10mb -e
show-tree D:/Projects -x '*.tmp'
```

```powershell
Show-Tree
Show-Tree D:\Projects -MaxDepth 2
Show-Tree D:\Projects -Long -MinSize 10MB -HideEmptyFolders
Show-Tree D:\Projects -Exclude "*.tmp"
```

## Filesystem semantics

PowerShell and Nushell share the same user-facing contract:

- sizes are logical file bytes;
- directory-entry metadata is not counted;
- maximum depth limits traversal and therefore affects totals;
- minimum size excludes files from both visible output and totals;
- directories are ordered before files, case-insensitively by name;
- directory symbolic links are not recursively traversed;
- `--hide-empty-folders` / `-HideEmptyFolders` is evaluated after the active filters;
- Windows filesystem roots receive a meaningful root name instead of an empty basename.

The Nushell backend uses structured `du --long` data and normalizes it before producing the public rows.

## Installation

### Nushell

For a normal installation or update:

```nu
nu ./install-show-tree.nu
```

For repair when the current `config.nu` cannot load:

```nu
nu --no-config-file ./install-show-tree.nu
```

The second form deliberately starts Nu without the user's configuration, allowing the installer to repair an older broken Show-Tree block.

### PowerShell and both-shell installation

```powershell
.\Install-ShowTree.ps1
```

Shell-specific installation is also available:

```powershell
.\Install-ShowTree.ps1 -PowerShellOnly
.\Install-ShowTree.ps1 -NushellOnly
```

The installer:

1. verifies the vendored R3CLI files against `dependencies.json`;
2. replaces an existing marked Show-Tree block **in place** rather than appending duplicates;
3. builds the complete candidate `config.nu` and checks it with `nu-check` before writing;
4. backs up the previous Nu config as `config.nu.show-tree.bak`;
5. refuses ambiguous or mismatched Show-Tree markers instead of guessing.

Open a new Nushell session after installation so the updated import and display integration are loaded.

## R3CLI dependency

Show-Tree vendors the exact PowerShell and Nushell R3CLI adapters it was tested against:

```text
vendor/
└── R3CLI/
    ├── powershell/
    └── nushell/
```

The pinned source revision, version and SHA256 hashes live in `dependencies.json`. Users do not need another `R3CLI` directory beside Show-Tree.

Maintainers update the vendored dependency explicitly from a clean R3CLI checkout:

```console
python scripts/update_r3cli.py <clean-R3CLI-checkout>
```

Python is required for that maintainer operation only.

## Architecture

```text
show-tree.nu
  traversal + normalization + native Nu rows
          │
          ├── redirected/captured ──> normal Nu pipeline
          │
          └── direct REPL result ───> metadata marker
                                        │
                                        ▼
show-tree-display.nu ───────────────> R3CLI tree

Show-Tree.ps1 ──────────────────────> PowerShell tree implementation
```

Keeping display integration outside the main Nu module means scripts can import the command without automatically changing their global display hook.

## Development

CI targets Nushell 0.115.1 and Windows PowerShell integration. The suite covers:

- native flat output and serialization;
- explicit `table` readability;
- direct R3CLI rendering in a real pseudo-terminal REPL;
- `$ans.last` redisplay;
- preservation of the normal Nushell display hook;
- broken previous-install repair and config backup;
- idempotent reinstall;
- R3CLI dependency-integrity rejection;
- PowerShell profile installation.

Run the structured Nu test directly with:

```nu
nu tests/Nushell.Structured.nu
```

## Requirements

- Nushell 0.115+ for the Nushell command;
- PowerShell 7 for the PowerShell command and shared installer;
- Windows for profile installation and the legacy `tree.com` forwarding wrapper.

## Licence

MIT. See [`LICENSE`](LICENSE) if present in the distribution.
