# Show-Tree

[![Test](https://github.com/R3Neer/Show-Tree/actions/workflows/test.yml/badge.svg)](https://github.com/R3Neer/Show-Tree/actions/workflows/test.yml)

A size-aware filesystem tree for PowerShell and Nushell, rendered with R3CLI while preserving native Nushell data for pipelines.

## Default behavior

`show-tree` now means the complete tree. With no visibility or depth filters it includes:

- directories;
- files;
- hidden and dot-prefixed entries;
- every descendant recursively, with no depth limit.

```nu
show-tree D:/Tools
```

The historical `--long` / `-l` and `--all` / `-a` switches remain accepted for compatibility, but their old opt-in behavior is now the default. They are therefore no-ops in 0.1.3. Explicit filters still work normally:

```nu
show-tree D:/Tools -d 3
show-tree D:/Tools -m 10mb -e
show-tree D:/Tools -x '*.tmp'
```

PowerShell follows the same contract:

```powershell
Show-Tree D:\Tools
Show-Tree D:\Tools -MaxDepth 3
```

## Nushell data model

The tree is a presentation of native data, not a text-only mode.

```text
show-tree
   │
   ▼
native rows + private lineage metadata
   │
   ├── direct REPL result ────────────────> R3CLI tree
   ├── where / sort-by / take / reverse ──> rebuilt R3CLI tree
   ├── save tree.txt ─────────────────────> human tree as UTF-8 text
   ├── save snapshot.showtree ────────────> native persistent snapshot
   ├── to json / to nuon ─────────────────> explicit machine representation
   └── table ─────────────────────────────> explicit Nushell table
```

The public row contract is:

```nu
{
    name: string
    type: 'dir' | 'file'
    size: filesize
    children: list<string>
    path: string
}
```

Every visible filesystem node is one top-level row. `children` contains direct child names, never nested records.

## Tree-first pipelines

Row-preserving transformations keep the tree view:

```nu
show-tree D:/Tools
| where size > 10mb
| sort-by size --reverse
```

The renderer uses exactly the rows that remain. Removed nodes are never reintroduced. If a retained node loses its parent, it is attached to the nearest retained ancestor; if none remains, it becomes a visual root labelled with its full path.

Hierarchy wins over impossible sort orders: parents stay above descendants while transformed row order still controls roots and siblings where possible.

Use `table` when you explicitly want the flat Nu table:

```nu
show-tree D:/Tools | table
```

Shape-changing commands such as `get size`, `group-by`, or a `select` that removes required tree fields fall back to normal Nushell display.

## Saving the human tree

A normal filename saves the same human tree shown in the REPL:

```nu
show-tree D:/Tools | save tree.txt
```

Filtered and sorted trees save as the filtered and sorted drawing:

```nu
show-tree D:/Tools
| where size > 10mb
| sort-by size --reverse
| save large-tree.txt
```

The file contains Unicode tree glyphs but no ANSI colour escapes. There is no `to tree`, `--render`, or Show-Tree-specific output-path option.

PowerShell uses its ordinary pipeline:

```powershell
Show-Tree D:\Tools | Set-Content tree.txt
```

## Native `.showtree` snapshots

Use `.showtree` when the goal is to persist the native Show-Tree value rather than its drawing:

```nu
show-tree D:/Tools | save tools.showtree
```

The extension is never appended automatically. A `.showtree` snapshot stores a versioned NUON envelope containing the rows and enough effective lineage to reconstruct the same forest later:

```nu
{
    format: show-tree
    schema_version: 1
    producer_version: 0.1.3
    rows: [...]
    lineage: [...]
}
```

Open it normally:

```nu
open tools.showtree
```

The rows and Show-Tree metadata are restored, so the result immediately renders as a tree and remains pipeline-friendly:

```nu
open tools.showtree
| where type == file
| where size > 1mb
```

A snapshot is not a live filesystem pointer. Reopening it does not rescan disk.

Filtered snapshots contain only the rows that survived the pipeline, with their effective hierarchy recalculated:

```nu
show-tree D:/Tools
| where name in [src main.nu]
| save subset.showtree
```

Explicit conversion is also available:

```nu
show-tree D:/Tools | to showtree
open --raw tools.showtree | from showtree
```

`--raw` keeps its normal Nushell meaning. `open --raw file.showtree` bypasses `from showtree`; `save --raw file.showtree` bypasses the custom serializer and delegates to builtin raw saving. `%save` remains the explicit builtin escape hatch.

## Other machine formats

JSON and NUON remain explicit conversions of the public rows:

```nu
show-tree D:/Tools | to json | save tree.json
show-tree D:/Tools | to nuon | save tree.nuon
```

Private lineage does not leak into those representations.

## `$ans.last`

When `max_last_result_size` permits it, Show-Tree participates in Nushell's normal last-result behavior:

```nu
show-tree D:/Tools | where size > 10mb
$ans.last
```

Both render the filtered tree. Use `$ans.last | table` to inspect the flat rows explicitly.

## Options

| Behaviour | PowerShell | Nushell |
| --- | --- | --- |
| Starting paths | positional / `Path` | positional |
| Dereference links for size metadata | `-Dereference`, `-r` | `--deref`, `-r` |
| Legacy completeness switch | `-Long`, `-l` | `--long`, `-l` |
| Exclude matching file paths | `-Exclude`, `-x` | `--exclude`, `-x` |
| Maximum traversal depth | `-MaxDepth`, `-d` | `--max-depth`, `-d` |
| Minimum included file size | `-MinSize`, `-m` | `--min-size`, `-m` |
| Legacy hidden-entry switch | `-All`, `-a` | `--all`, `-a` |
| Hide folders with no included files | `-HideEmptyFolders`, `-e` | `--hide-empty-folders`, `-e` |
| Help | `-Help`, `-h` | `--help`, `-h` |

`Long` and `All` are retained only for backwards compatibility. Files and hidden entries are included by default.

## Installation

Nushell:

```nu
nu ./install-show-tree.nu
```

Repair a broken existing Show-Tree block without loading `config.nu`:

```nu
nu --no-config-file ./install-show-tree.nu
```

PowerShell or both-shell installation:

```powershell
.\Install-ShowTree.ps1
.\Install-ShowTree.ps1 -PowerShellOnly
.\Install-ShowTree.ps1 -NushellOnly
```

The installer validates vendored dependency hashes, replaces the marked profile/config block in place, validates candidate Nushell config with `nu-check`, creates a backup, and refuses ambiguous markers.

Open a new Nushell session after installation. The parent Nu process that launched the installer cannot hot-reload command definitions already in memory.

## Repository layout

Implementation code is kept out of the repository root:

```text
Show-Tree/
├── src/
│   ├── nushell/
│   │   ├── show-tree.nu
│   │   ├── show-tree-display.nu
│   │   ├── show-tree-format.nu
│   │   └── show-tree-save.nu
│   └── powershell/
│       └── Show-Tree.ps1
├── tests/
├── scripts/
├── docs/
├── vendor/
├── Install-ShowTree.ps1
├── install-show-tree.nu
├── dependencies.json
└── README.md
```

The root is reserved for user-facing installers, documentation and repository metadata. The installer points directly to `src/`.

The Nushell implementation is intentionally split by concern:

- `show-tree.nu`: traversal, normalization and native row contract;
- `show-tree-display.nu`: REPL presentation and tree reconstruction;
- `show-tree-format.nu`: `.showtree`, `to showtree`, `from showtree`;
- `show-tree-save.nu`: tree-aware `save` dispatch.

R3CLI remains vendored and SHA-verified under `vendor/R3CLI/`.

## Development

CI targets Nushell 0.115.1 and Windows PowerShell integration. Coverage includes:

- complete no-flag traversal with files, hidden entries and deep descendants;
- explicit depth/filter behavior after the default change;
- native flat output and direct child lists;
- filtered reconstruction, orphan promotion, sorting and `$ans.last`;
- human-tree saving;
- `.showtree` save/open round trips and raw semantics;
- real pseudo-terminal rendering of direct and reopened trees;
- PowerShell default completeness and pipeline-to-file output;
- installer repair, config backup and idempotence;
- vendored R3CLI integrity rejection.

## Requirements

- Nushell 0.115+ for Nushell integration and `.showtree`;
- PowerShell 7 for PowerShell integration and the shared installer;
- Windows for profile installation and the legacy `tree.com` forwarding wrapper.
