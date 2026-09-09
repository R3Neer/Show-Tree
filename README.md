# Show-Tree

[![Test](https://github.com/R3Neer/Show-Tree/actions/workflows/test.yml/badge.svg)](https://github.com/R3Neer/Show-Tree/actions/workflows/test.yml)

A size-aware filesystem tree for PowerShell and Nushell, with an R3CLI terminal view for humans and native Nushell rows for pipelines.

Show-Tree is built around one rule: **the tree is a presentation of native data, not a separate text-only mode**.

```text
show-tree
   │
   ▼
native Nushell rows + private lineage metadata
   │
   ├── direct REPL result ────────────────> R3CLI tree
   ├── where / sort-by / take / reverse ──> rebuilt R3CLI tree
   ├── save tree.txt ─────────────────────> same tree as plain UTF-8 text
   ├── save snapshot.showtree ────────────> native persistent snapshot
   ├── to json / to nuon ─────────────────> explicit machine representation
   └── table ─────────────────────────────> explicit Nushell table
```

R3CLI is bundled as a verified private dependency. Users do not need a separate R3CLI checkout or Python runtime.

## Quick start

```nu
show-tree D:/Tools -d 2
```

A direct result is rendered as a tree:

```text
SHOW-TREE
D:\Tools [Folder] (...)
├── ModpackTools [Folder] (...)
├── R3CLI [Folder] (...)
└── Show-Tree [Folder] (...)

Total size       ...
```

The value underneath is still ordinary Nushell data. Ask for a table explicitly:

```nu
show-tree D:/Tools -d 2 | table
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

Every visible filesystem node is one top-level row. `children` contains only direct child names, never nested child records, so explicit tables do not collapse into `[table 36 rows]` archaeology.

## Tree-first pipelines

Representable row-preserving transformations keep the tree view:

```nu
show-tree D:/Tools -d 3 -l
| where size > 10mb
| sort-by size --reverse
```

```nu
show-tree D:/Tools -d 3
| where type == dir
| take 10
```

The renderer uses exactly the rows that remain. It never resurrects a node removed by `where`, `take`, `drop`, or another filter.

If a retained node loses its parent, Show-Tree attaches it to the nearest retained ancestor. If no retained ancestor exists, it becomes a visual root and is labelled with its full path. Sorting is hierarchy-safe: parents stay above descendants, while the transformed row order controls roots and siblings where the hierarchy allows it.

The automatic tree view requires the semantic fields `name`, `type`, `size`, and `path` plus Show-Tree metadata. Thus this remains a tree:

```nu
show-tree D:/Tools -d 2 | reject children
```

but this no longer contains enough information to draw one and falls back to normal Nu display:

```nu
show-tree D:/Tools -d 2 | select name size
```

Shape-changing commands such as `get size` or `group-by` likewise use Nushell's normal representation.

## Saving a human tree

The installed `save` wrapper makes the obvious command do the obvious thing:

```nu
show-tree D:/Tools -d 3 -l | save tree.txt
```

The file contains the same human tree shown by the REPL, including Unicode branches, sizes, banner and total, but without ANSI colour escapes.

Transformed results save truthfully too:

```nu
show-tree D:/Tools -d 4 -l
| where size > 1mb
| sort-by size --reverse
| save large-tree.txt
```

There is no `to tree`, `--render`, or Show-Tree-specific output-path option. If the target is not `.showtree`, a representable Show-Tree value is saved as the drawing.

For unrelated values the wrapper delegates to Nushell's builtin `%save`, preserving the normal `--raw`, `--append`, `--force`, `--stderr`, and `--progress` semantics.

## Native `.showtree` snapshots

Use the `.showtree` extension when the goal is not a drawing but a persistent Show-Tree value:

```nu
show-tree D:/Tools -d 3 -l | save tools.showtree
```

The extension is **never added automatically**. A filename such as `tools.txt`, `tools.log`, or simply `tools` keeps the normal human-tree save behavior. Persistence is explicit either through `.showtree` or through `to showtree`.

A `.showtree` file stores a versioned NUON envelope containing:

```nu
{
    format: show-tree
    schema_version: 1
    producer_version: 0.1.2
    rows: [...]
    lineage: [...]
}
```

NUON is an implementation detail, but it matters for one useful reason: Nushell-native values such as `filesize` survive the round trip without inventing a second type system inside JSON.

Open the snapshot normally:

```nu
open tools.showtree
```

Because the installer imports `from showtree`, Nushell's normal custom-format discovery parses the file and restores the native rows plus Show-Tree metadata. The result therefore renders immediately as the R3CLI tree.

It is still data, so normal pipelines continue to work:

```nu
open tools.showtree
| where size > 10mb
| sort-by size --reverse
```

That produces a newly reconstructed tree from the persisted rows. The filesystem is not rescanned. A `.showtree` file is a snapshot, not a live pointer to the original directory.

### Filtered snapshots are snapshots of the filter

```nu
show-tree D:/Tools -d 4 -l
| where name in [src main.nu]
| save subset.showtree
```

Only the surviving rows are stored. Show-Tree recomputes the effective parent relation from those surviving filesystem paths, so omitted ancestors do not linger invisibly inside the file. Reopening `subset.showtree` reproduces that filtered forest as its new baseline.

### Explicit conversion

The same format can be requested without relying on a filename extension:

```nu
show-tree D:/Tools -d 3 -l | to showtree
```

and parsed explicitly with:

```nu
open --raw tools.showtree | from showtree
```

This is useful when the serialized text travels through another channel rather than directly to a `.showtree` file.

### `--raw` keeps its Nushell meaning

Show-Tree does not overload `--raw`.

```nu
open --raw tools.showtree
```

bypasses `from showtree` and returns the raw serialized envelope, exactly as `open --raw` bypasses parsers for other formats.

Likewise:

```nu
show-tree D:/Tools -l | save --raw tools.showtree
```

bypasses the `.showtree` serializer and delegates the original value to builtin `%save --raw`. Whether that raw value can be written is therefore governed by Nushell's ordinary raw-save rules, not by a second Show-Tree-specific meaning.

`%save` remains available when the builtin command itself is wanted explicitly. For `.showtree` without `--raw`, builtin save can still discover `to showtree` because that converter is installed in scope.

## Explicit machine formats

JSON and NUON remain ordinary explicit conversions:

```nu
show-tree D:/Tools -d 3 -l | to json | save tree.json
show-tree D:/Tools -d 3 -l | to nuon | save tree.nuon
```

Once `to json`, `to nuon`, `table`, or another renderer consumes the native rows, the value is no longer a Show-Tree object and `save` behaves normally.

Private lineage fields such as `parent_path` do not leak into the public table, JSON, or NUON row contract. The `.showtree` format is the deliberate exception because persistence needs enough hierarchy information to restore the tree identity later.

## `$ans.last`

When `max_last_result_size` allows it, direct and transformed Show-Tree results participate in Nushell's normal last-result machinery:

```nu
show-tree D:/Tools -d 3 -l | where size > 10mb
$ans.last
```

Both render as the filtered tree. To inspect the last value as rows:

```nu
$ans.last | table
```

If repeated experimentation matters, capture the native value before running a renderer such as `table`:

```nu
let tree = $ans.last
$tree | table
$tree | where type == dir
```

## PowerShell

PowerShell keeps its human-oriented contract:

```powershell
Show-Tree D:\Tools -MaxDepth 3
```

and piping the installed wrapper exposes plain tree lines on the success pipeline:

```powershell
Show-Tree D:\Tools -MaxDepth 3 | Set-Content tree.txt
```

No Show-Tree-specific output option is needed. `.showtree` persistence is a Nushell-native feature and does not add a parallel PowerShell file format API.

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
show-tree D:/Projects -d 3 -l | save projects.showtree
```

```powershell
Show-Tree
Show-Tree D:\Projects -MaxDepth 2
Show-Tree D:\Projects -Long -MinSize 10MB -HideEmptyFolders
Show-Tree D:\Projects -Exclude "*.tmp"
```

## Filesystem semantics

PowerShell and Nushell share the same traversal contract:

- sizes are logical file bytes;
- directory-entry metadata is not counted;
- maximum depth limits traversal and therefore affects totals;
- minimum size excludes files from visible output and totals;
- directories are initially ordered before files, case-insensitively by name;
- directory symbolic links are not recursively traversed;
- `--hide-empty-folders` / `-HideEmptyFolders` is evaluated after active traversal filters;
- filesystem roots render using their full path, so a Windows root such as `D:\` never becomes a blank label.

The Nushell backend uses structured `du --long` data and normalizes it before producing public rows.

## Installation

### Nushell

Normal installation or update:

```nu
nu ./install-show-tree.nu
```

Repair when the current `config.nu` cannot load:

```nu
nu --no-config-file ./install-show-tree.nu
```

The generated Show-Tree block imports four concerns separately:

```text
show-tree.nu          traversal + native rows
show-tree-display.nu  REPL display hook
show-tree-format.nu   to showtree / from showtree
show-tree-save.nu     user-facing save dispatch
```

Keeping those pieces separate means scripts may import the traversal module alone without silently changing global display, persistence, or save behavior.

The installer replaces its marked block in place, validates the complete candidate `config.nu` with `nu-check`, backs up the previous config as `config.nu.show-tree.bak`, and refuses ambiguous markers instead of guessing.

Open a **new Nushell session** after installation. An already-running parent Nu process keeps the command definitions it loaded earlier and cannot be hot-reloaded by a child installer.

### PowerShell and both-shell installation

```powershell
.\Install-ShowTree.ps1
```

Shell-specific installation:

```powershell
.\Install-ShowTree.ps1 -PowerShellOnly
.\Install-ShowTree.ps1 -NushellOnly
```

## R3CLI dependency

Show-Tree vendors the exact PowerShell and Nushell R3CLI adapters it was tested against:

```text
vendor/
└── R3CLI/
    ├── powershell/
    └── nushell/
```

The pinned source revision, version, and SHA256 hashes live in `dependencies.json`. Maintainers update the vendored dependency explicitly from a clean R3CLI checkout:

```console
python scripts/update_r3cli.py <clean-R3CLI-checkout>
```

Python is required for that maintainer operation only.

## Architecture

```text
show-tree.nu
  traversal + normalization
          │
          ▼
native rows + transient lineage metadata
          │
          ├──────── normal Nu pipeline ────────┐
          │                                    │
          ▼                                    ▼
show-tree-display.nu                    show-tree-save.nu
  REPL reconstruction                   ├── .showtree -> structured snapshot
          │                             └── other name -> human tree text
          ▼                                    │
      R3CLI tree                               ▼
                                         builtin %save

show-tree-format.nu
  ├── to showtree   -> versioned NUON envelope
  └── from showtree -> validated rows + restored Show-Tree metadata
```

The `.showtree` envelope stores current rows plus only the effective path-parent relation required to reconstruct the persisted forest. It does not preserve removed rows as secret historical state.

## Development

CI targets Nushell 0.115.1 and Windows PowerShell integration. Coverage includes:

- native flat output, direct child lists, and explicit serialization;
- R3CLI rendering in a real pseudo-terminal REPL;
- filtered reconstruction, orphan promotion, sorting, and `$ans.last`;
- human tree saving for original and transformed results;
- `.showtree` save/open round trips and explicit `to showtree` / `from showtree`;
- filtered snapshot lineage and reopened-tree filtering;
- `open --raw` and unsupported-schema rejection;
- unrelated builtin-save delegation and explicit JSON workflows;
- installed format/parser/save imports and installed `.showtree` reopening;
- broken-install repair, config backup, and idempotent reinstall;
- PowerShell pipeline-to-file output without ANSI escapes;
- vendored R3CLI integrity rejection.

Run the structured Nu test directly with:

```nu
nu tests/Nushell.Structured.nu
```

## Requirements

- Nushell 0.115+ for the Nushell command and `.showtree` format;
- PowerShell 7 for the PowerShell command and shared installer;
- Windows for profile installation and the legacy `tree.com` forwarding wrapper.
