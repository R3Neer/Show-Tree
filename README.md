# Show-Tree

[![Test](https://github.com/R3Neer/Show-Tree/actions/workflows/test.yml/badge.svg)](https://github.com/R3Neer/Show-Tree/actions/workflows/test.yml)

A size-aware filesystem tree for PowerShell and Nushell, rendered with R3CLI while preserving native Nushell data for pipelines.

## Default behavior

`show-tree` shows the recursive visible tree. With no filters it includes:

- directories;
- files;
- every visible descendant recursively;
- no depth limit.

Hidden and dot-prefixed entries are deliberately omitted by default. Use `--all` / `-a` in Nushell or `-All` / `-a` in PowerShell to include them.

```nu
show-tree D:/Tools
show-tree D:/Tools --all
```

```powershell
Show-Tree D:\Tools
Show-Tree D:\Tools -All
```

When hidden entries are being omitted, the interactive tree shows a short reminder:

```text
! Hidden entries are omitted. Use --all (-a) to include them.
```

That reminder belongs to the terminal presentation, not to the tree data. It is therefore not written when the tree is saved to a file or piped through PowerShell.

Files are part of the normal tree. There is no `--long` / `-Long` mode. If a directory-only view is wanted, use `--short` / `-s` in Nushell or `-Short` / `-s` in PowerShell:

```nu
show-tree D:/Tools --short
```

```powershell
Show-Tree D:\Tools -Short
```

`short` suppresses file rows only. Directory sizes still account for the visible files beneath them, so the size information remains useful instead of becoming decorative arithmetic.

Explicit filters continue to work normally:

```nu
show-tree D:/Tools -d 3
show-tree D:/Tools -m 10mb -e
show-tree D:/Tools -x '*.tmp'
show-tree D:/Tools --all --short
```

## Nushell data model

The tree is a presentation of native data, not a text-only mode.

```text
show-tree
   │
   ▼
native rows + private lineage metadata
   │
   ├── direct REPL result ────────────────> R3CLI tree + interactive notice when applicable
   ├── where / sort-by / take / reverse ──> rebuilt R3CLI tree
   ├── save tree.txt ─────────────────────> human tree as UTF-8 text, no notice
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

The hidden-entry reminder is tracked only as private presentation metadata on live Show-Tree results. It does not become another public column and does not leak into JSON, NUON, tables or saved tree text.

## Tree-first pipelines

Row-preserving transformations keep the tree view:

```nu
show-tree D:/Tools
| where size > 10mb
| sort-by size --reverse
```

The renderer uses exactly the rows that remain. Removed nodes are never reintroduced. If a retained node loses its parent, it is attached to the nearest retained ancestor; if none remains, it becomes a visual root labelled with its full path.

Hierarchy wins over impossible sort orders: parents stay above descendants while transformed row order still controls roots and siblings where possible.

The visibility policy also survives row-preserving transformations. Thus a filtered result originating from `show-tree` still reminds the user that hidden entries were omitted, while a result originating from `show-tree --all` does not.

Use `table` when you explicitly want the flat Nu table:

```nu
show-tree D:/Tools | table
```

Shape-changing commands such as `get size`, `group-by`, or a `select` that removes required tree fields fall back to normal Nushell display.

## Saving the human tree

A normal filename saves the human tree:

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

The saved file contains Unicode tree glyphs, sizes, banner and total, but no ANSI colour escapes and no interactive hidden-entry reminder.

If hidden entries should be part of the saved drawing, include them before saving:

```nu
show-tree D:/Tools --all | save tree-with-hidden.txt
```

PowerShell uses its ordinary pipeline:

```powershell
Show-Tree D:\Tools | Set-Content tree.txt
Show-Tree D:\Tools -All | Set-Content tree-with-hidden.txt
```

The PowerShell reminder is interactive-only as well and is not part of piped tree output.

There is no `to tree`, `--render`, or Show-Tree-specific output-path option. Saving belongs to the shell pipeline.

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
    producer_version: 0.1.4
    rows: [...]
    lineage: [...]
}
```

Visibility is resolved before persistence. Therefore:

```nu
show-tree D:/Tools | save visible.showtree
show-tree D:/Tools --all | save all.showtree
show-tree D:/Tools --short | save directories.showtree
```

produce different snapshots containing exactly the rows requested by each command. The interactive hidden-entry reminder itself is not persisted.

Open a snapshot normally:

```nu
open tools.showtree
```

The rows and Show-Tree lineage metadata are restored, so the result immediately renders as a tree and remains pipeline-friendly:

```nu
open tools.showtree
| where type == file
| where size > 1mb
```

A snapshot is not a live filesystem pointer. Reopening it does not rescan disk, so `--all` and `--short` apply when the snapshot is created, not when an existing snapshot is opened.

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

Private lineage and presentation metadata do not leak into those representations.

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
| Directories-only view | `-Short`, `-s` | `--short`, `-s` |
| Exclude matching file paths | `-Exclude`, `-x` | `--exclude`, `-x` |
| Maximum traversal depth | `-MaxDepth`, `-d` | `--max-depth`, `-d` |
| Minimum included file size | `-MinSize`, `-m` | `--min-size`, `-m` |
| Include hidden entries | `-All`, `-a` | `--all`, `-a` |
| Hide folders with no included files | `-HideEmptyFolders`, `-e` | `--hide-empty-folders`, `-e` |
| Help | `-Help`, `-h` | `--help`, `-h` |

Default recursion is unlimited. `--short` changes row visibility, not traversal or size accounting. `--all` changes the filesystem visibility policy before rows are built.

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

The Nushell backend requests complete structured `du --long --all` data internally and applies Show-Tree's visibility policy before public rows are created. Dot-prefixed entries are filtered directly; on Windows, Show-Tree also consults Nushell's platform-native `ls` visibility so the filesystem Hidden attribute is respected. The internal `du --long` flag is a backend implementation detail, not a Show-Tree user option.

PowerShell enumerates with `Get-ChildItem -Force` and applies the same Show-Tree visibility policy itself. On Windows, `-All` includes both dot-prefixed names and entries carrying the filesystem Hidden attribute.

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

- `show-tree.nu`: traversal, visibility policy, normalization and native row contract;
- `show-tree-display.nu`: REPL presentation, reconstruction and interactive-only notices;
- `show-tree-format.nu`: `.showtree`, `to showtree`, `from showtree`;
- `show-tree-save.nu`: tree-aware `save` dispatch without presentation notices.

R3CLI remains vendored and SHA-verified under `vendor/R3CLI/`.

## Development

CI targets Nushell 0.115.1 and Windows PowerShell integration. Coverage includes:

- visible files and deep descendants in the no-flag tree;
- dot-prefixed and Windows Hidden-attribute exclusion by default and inclusion through `all`;
- directories-only `short` output with size accounting preserved;
- interactive hidden-entry reminders and their absence from saved/piped tree output;
- explicit depth and filtering behavior;
- native flat output and direct child lists;
- filtered reconstruction, orphan promotion, sorting and `$ans.last`;
- human-tree saving;
- `.showtree` save/open round trips and raw semantics;
- real pseudo-terminal rendering of direct and reopened trees;
- PowerShell pipeline-to-file output;
- installer repair, config backup and idempotence;
- vendored R3CLI integrity rejection.

## Requirements

- Nushell 0.115+ for Nushell integration and `.showtree`;
- PowerShell 7 for PowerShell integration and the shared installer;
- Windows for profile installation and the legacy `tree.com` forwarding wrapper.
