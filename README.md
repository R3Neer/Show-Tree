# Show-Tree

[![Test](https://github.com/R3Neer/Show-Tree/actions/workflows/test.yml/badge.svg)](https://github.com/R3Neer/Show-Tree/actions/workflows/test.yml)

A size-aware filesystem tree for PowerShell and Nushell, rendered with R3CLI while preserving native Nushell data for pipelines.

## Default behavior

`show-tree` shows visible directories and files recursively with no depth limit. Hidden and dot-prefixed entries are omitted unless `--all` / `-a` is used in Nushell or `-All` / `-a` in PowerShell.

```nu
show-tree D:/Tools
show-tree D:/Tools --all
show-tree D:/Tools --short
```

```powershell
Show-Tree D:\Tools
Show-Tree D:\Tools -All
Show-Tree D:\Tools -Short
```

`short` suppresses file rows but keeps directory sizes based on the visible files beneath them. There is no user-facing `long` mode because files are already normal output.

When hidden entries are omitted, the interactive tree shows a reminder:

```text
! Hidden entries are omitted. Use --all (-a) to include them.
```

That reminder is presentation-only. It is not a public data field and is not written by tree-aware `save` or PowerShell pipeline output.

## Human tree

Directories use a Unicode folder glyph instead of a textual type suffix:

```text
📁 D:\Tools\Show-Tree (2.64 MiB)
├── 📁 docs (42.00 KiB)
├── 📁 src (104.00 KiB)
│   ├── 📁 nushell (72.00 KiB)
│   └── 📁 powershell (32.00 KiB)
└── README.md (14.00 KiB)
```

`📁` is presentation only. Files remain visually lighter and do not receive a redundant file icon. The old `[Folder]` label is no longer emitted.

Saving to an ordinary filename writes the same human tree without ANSI colour escapes or the interactive hidden-entry reminder:

```nu
show-tree D:/Tools | save tree.txt
```

Filtered and sorted trees save exactly the rows that survive the pipeline:

```nu
show-tree D:/Tools
| where size > 10mb
| sort-by size --reverse
| save large-tree.txt
```

PowerShell uses its normal pipeline:

```powershell
Show-Tree D:\Tools | Set-Content tree.txt
```

## Nushell data model

The tree is a presentation of native data, not a text-only mode. The public row contract is:

```nu
{
    name: string
    type: 'dir' | 'file'
    size: filesize
    children: list<string>
    path: string
}
```

Every visible filesystem node is one top-level row. `children` contains direct child names, never nested records. Private metadata carries lineage and presentation state needed to reconstruct the human tree.

This means the following all remain ordinary Nushell operations:

```nu
show-tree D:/Tools | where size > 10mb
show-tree D:/Tools | sort-by size --reverse
show-tree D:/Tools | table
show-tree D:/Tools | to json
```

Row-preserving transformations such as `where`, `sort-by`, `take`, `drop`, and `reverse` keep the tree view when the result remains representable. Removed nodes are never reintroduced. A retained descendant whose original parent is gone is attached to its nearest retained ancestor; if none remains, it becomes a visual root labelled with its full path.

Shape-changing operations such as `get size`, `group-by`, or a `select` that removes required tree fields fall back to normal Nushell display.

## Native `.showtree` snapshots

Use `.showtree` when the goal is to persist the native Show-Tree value rather than the drawing:

```nu
show-tree D:/Tools | save tools.showtree
```

The extension is never appended automatically. A snapshot stores a versioned NUON envelope containing the public rows and enough effective lineage to restore the same forest:

```nu
{
    format: show-tree
    schema_version: 1
    producer_version: 0.1.5
    rows: [...]
    lineage: [...]
}
```

Open it normally:

```nu
open tools.showtree
```

The result immediately renders as a tree again and remains pipeline-friendly:

```nu
open tools.showtree
| where type == file
| where size > 1mb
```

Snapshots contain exactly the rows selected when they are created:

```nu
show-tree D:/Tools | save visible.showtree
show-tree D:/Tools --all | save all.showtree
show-tree D:/Tools --short | save directories.showtree
```

A snapshot is not a live filesystem pointer. Reopening it does not rescan disk.

Explicit conversion is also available:

```nu
show-tree D:/Tools | to showtree
open --raw tools.showtree | from showtree
```

`--raw` keeps its normal Nushell meaning. `%save` remains the explicit escape hatch to the builtin command.

## `$ans.last`

When `max_last_result_size` permits it, Show-Tree participates in Nushell's normal last-result behavior:

```nu
show-tree D:/Tools | where size > 10mb
$ans.last
```

Both expressions render the filtered tree. Use `$ans.last | table` to inspect the flat rows explicitly.

## Options

| Behaviour | PowerShell | Nushell |
| --- | --- | --- |
| Starting paths | positional / `Path` | positional |
| Dereference links for size metadata | `-Dereference`, `-r` | `--deref`, `-r` |
| Directories-only view | `-Short`, `-s` | `--short`, `-s` |
| Exclude matching file paths | `-Exclude`, `-x` | `--exclude`, `-x` |
| Maximum traversal depth | `-MaxDepth`, `-d` | `--max-depth`, `-d` |
| Minimum included file size | `-MinSize`, `-m` | `--min-size`, `-m` |
| Include hidden entries | `-All`, `-a` | `--all`, `-a` |
| Hide folders with no included files | `-HideEmptyFolders`, `-e` | `--hide-empty-folders`, `-e` |
| Help | `-Help`, `-h` | `--help`, `-h` |

## Filesystem semantics

PowerShell and Nushell share the same user-facing contract:

- visible files and directories are included by default;
- hidden/dot-prefixed entries require `all`;
- recursion is unlimited unless maximum depth is supplied;
- `short` suppresses file rows but preserves directory size accounting;
- minimum size removes files from output and totals;
- exclusions are applied before public rows are built;
- directories are ordered before files, case-insensitively by name;
- directory symbolic links are not recursively traversed;
- empty-folder hiding is evaluated after active traversal filters;
- filesystem roots render using their full path.

The Nushell backend requests complete structured `du --long --all` data internally and applies Show-Tree's visibility policy before public rows are created. On Windows it also consults Nushell's native `ls` visibility so the filesystem Hidden attribute is respected. The internal `du --long` flag is an implementation detail, not a Show-Tree option.

PowerShell enumerates with `Get-ChildItem -Force` and applies the same policy itself.

## Renderer performance

The Nushell renderer builds indexes for visible paths, lineage, and effective parent groups once per render. It no longer scans all visible rows again for every node just to discover its children, and parent resolution no longer scans the complete lineage for every lookup.

A synthetic flat-tree benchmark on GitHub Actions measured:

| Rows | Previous renderer | Indexed renderer |
| ---: | ---: | ---: |
| 501 | ~1.108 s | ~0.503 s |
| 2,001 | ~11.701 s | ~2.195 s |

A 4× input increase therefore changed from roughly 10.6× runtime growth to about 4.4× end-to-end growth. The isolated render-plan benchmark measured about 146 ms for 2,001 rows and 779 ms for 8,001 rows.

CI enforces both absolute and scaling ceilings. Filesystem traversal is benchmarked separately on Windows. A proposed filename-index optimization for Windows traversal was rejected after measurement because it made the 1,500-file default case slower, about 828 ms to 982 ms on the measured runners. The benchmark, rather than the attractiveness of the data structure on a whiteboard, won that argument.

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

The Nushell implementation is split by concern:

- `show-tree.nu`: traversal, visibility policy, normalization and native rows;
- `show-tree-display.nu`: indexed tree reconstruction and REPL presentation;
- `show-tree-format.nu`: `.showtree`, `to showtree`, `from showtree`;
- `show-tree-save.nu`: tree-aware `save` dispatch.

R3CLI remains vendored and SHA-verified under `vendor/R3CLI/`.

## Development

CI targets Nushell 0.115.1 and PowerShell 7. Coverage includes structured rows, filtering/sorting/orphan promotion, `$ans.last`, `.showtree`, raw semantics, real pseudo-terminal rendering, hidden-entry behavior, folder-glyph output, installer repair/idempotence, PowerShell pipeline output, renderer scaling, and Windows traversal performance.

Performance tests live in:

```text
tests/Nushell.Performance.nu
tests/Nushell.TraversalPerformance.nu
```

## Requirements

- Nushell 0.115+ for Nushell integration and `.showtree`;
- PowerShell 7 for PowerShell integration and the shared installer;
- Windows for profile installation and the legacy `tree.com` forwarding wrapper.
