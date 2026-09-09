# Show-Tree

[![Test](https://github.com/R3Neer/Show-Tree/actions/workflows/test.yml/badge.svg)](https://github.com/R3Neer/Show-Tree/actions/workflows/test.yml)

A size-aware filesystem tree for PowerShell and Nushell, with an R3CLI terminal view for humans and native Nushell rows for pipelines.

Show-Tree is designed around one rule: **the tree is a presentation of native data, not a separate text-only mode**.

```text
show-tree
   │
   ▼
native Nushell rows + lineage metadata
   │
   ├── direct REPL result ────────────────> R3CLI tree
   ├── where / sort-by / take / reverse ──> R3CLI tree rebuilt from remaining rows
   ├── capture / JSON / NUON ─────────────> native data
   └── explicit `table` ──────────────────> Nushell table
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

The value behind that view is still native Nushell data. Ask for a table explicitly and the same traversal becomes one flat table:

```nu
show-tree D:/Tools -d 2 | table
```

```text
╭───┬──────────────┬──────┬──────────┬──────────────────────────────┬─────────────────────────╮
│ # │     name     │ type │   size   │           children           │          path           │
├───┼──────────────┼──────┼──────────┼──────────────────────────────┼─────────────────────────┤
│ 0 │ Tools        │ dir  │ ...      │ [ModpackTools R3CLI Show-…]  │ D:\Tools                │
│ 1 │ ModpackTools │ dir  │ ...      │ [...]                        │ D:\Tools\ModpackTools   │
│ 2 │ R3CLI        │ dir  │ ...      │ [...]                        │ D:\Tools\R3CLI          │
│ 3 │ Show-Tree    │ dir  │ ...      │ [...]                        │ D:\Tools\Show-Tree      │
╰───┴──────────────┴──────┴──────────┴──────────────────────────────┴─────────────────────────╯
```

There is **one row per visible filesystem node**. `children` is only a native list of that node's direct child names; it never contains nested records or nested child tables. You therefore get the relationship information without returning to `[table 36 rows]` archaeology.

Nushell may trim long cells when the terminal itself is narrow. That is ordinary `table` behaviour, not Show-Tree hiding descendants.

## Tree-first pipelines

Representable Show-Tree results keep the tree view through normal row-preserving Nu transformations:

```nu
show-tree D:/Tools -d 3 -l
| where size > 10mb
```

```nu
show-tree D:/Tools -d 3
| where type == dir
| take 10
```

```nu
show-tree D:/Tools -d 3 -l
| sort-by size --reverse
```

These pipelines still carry native rows. Only their automatic REPL representation is the tree.

### Filtering

The renderer uses **exactly the rows that remain**. It never reintroduces a node that `where`, `take`, `drop`, or another filter removed.

If a retained node's parent disappeared, Show-Tree attaches it to the nearest retained ancestor. If no retained ancestor exists, the node becomes a visual root and is labelled with its full path so the missing context is explicit.

### Sorting

Filesystem hierarchy has priority over a global row order. A parent is always rendered before its descendants, even if `sort-by` placed a child earlier in the flat table.

Within each sibling group, however, the order produced by the pipeline is preserved. Thus:

```nu
show-tree D:/Tools -d 3 -l
| sort-by size --reverse
```

means, in effect:

1. keep parents above descendants;
2. order visual roots by the transformed row order;
3. order siblings by that same transformed row order.

This gives `sort-by` useful visual meaning without creating trees where children float above their parents like a filesystem designed during a fever.

### When the tree view stops applying

The automatic tree renderer requires the semantic fields `name`, `type`, `size`, and `path`, plus Show-Tree's lineage metadata.

So this remains a tree:

```nu
show-tree D:/Tools -d 2
| reject children
```

but this no longer contains enough information to draw one:

```nu
show-tree D:/Tools -d 2
| select name size
```

and falls back to Nushell's normal display.

Likewise, commands that fundamentally change the shape, such as `get size` or `group-by`, are displayed normally by Nu.

## Explicit table and flattened data

To leave the automatic tree representation intentionally, pipe to `table`:

```nu
show-tree D:/Tools -d 3 -l | table
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

That is already the flattened form: every descendant is another row at the same table level. `children` contains direct **names**, not child records, so the relationship remains inspectable without nesting the data structure.

For example:

```nu
let tree = (show-tree D:/Tools -d 3 -l)

$tree
| where type == dir
| select name children path
| table
```

You can also work with the child lists natively:

```nu
show-tree D:/Tools -d 3 -l
| where ($it.children | length) > 0
| select name children
```

`children` describes the direct visible children in the original Show-Tree result. A later Nu filter removes rows but does not rewrite the fields of surviving rows, just as filtering any ordinary table does not mutate unrelated columns. The interactive renderer uses private lineage metadata rather than trusting the possibly filtered `children` list.

## `$ans.last`

A direct call stores the same native result in Nushell's last-result machinery when `max_last_result_size` allows it:

```nu
show-tree D:/Tools -d 2
$ans.last
```

Both lines render as the tree.

The same applies after a representable transformation:

```nu
show-tree D:/Tools -d 3 -l
| where size > 10mb

$ans.last
```

`$ans.last` redraws that **filtered** tree because the last result is the filtered native table, not the pre-filter traversal.

To inspect it explicitly as rows:

```nu
$ans.last | table
```

Remember that `table` itself produces rendered text. If you want to experiment repeatedly with the native value, keep a stable variable first:

```nu
let tree = $ans.last
$tree | table
$tree | where type == dir
```

## Machine-readable output

No dedicated JSON switch is needed:

```nu
show-tree D:/Tools -d 3 -l | to json
show-tree D:/Tools -d 3 -l | to nuon
```

The private lineage used for tree reconstruction is pipeline metadata, so fields such as `parent_path`, branch glyphs, and visual depth do not leak into JSON or the public table.

`name` is kept alongside the full `path` because it is the natural field for filtering and selection in Nu, while `path` stays available for filesystem actions. A root whose basename would otherwise be empty uses its full root path as its display name.

Without `--long`, file rows are omitted from the returned table, but file sizes still contribute to directory totals. `children` then lists only child nodes represented by that result, so omitted file rows are not quietly exposed through the child list.

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

PowerShell and Nushell share the same user-facing traversal contract:

- sizes are logical file bytes;
- directory-entry metadata is not counted;
- maximum depth limits traversal and therefore affects totals;
- minimum size excludes files from both visible output and totals;
- directories are initially ordered before files, case-insensitively by name;
- directory symbolic links are not recursively traversed;
- `--hide-empty-folders` / `-HideEmptyFolders` is evaluated after the active traversal filters;
- filesystem roots render using their full path, so a Windows root such as `D:\` never appears as a blank label.

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

The pinned source revision, version, and SHA256 hashes live in `dependencies.json`. Users do not need another `R3CLI` directory beside Show-Tree.

Maintainers update the vendored dependency explicitly from a clean R3CLI checkout:

```console
python scripts/update_r3cli.py <clean-R3CLI-checkout>
```

Python is required for that maintainer operation only.

## Architecture

```text
show-tree.nu
  traversal + normalization
          │
          ├── public flat rows: name / type / size / children / path
          │
          └── private lineage metadata: original parent relation
                           │
                           ▼
                   normal Nu pipeline
                           │
             where / sort / take / ...
                           │
                           ▼
show-tree-display.nu
  ├── representable result ──> rebuild current forest ──> R3CLI tree
  └── other result ──────────> previous/default Nu display

explicit `table` / JSON / NUON consume the native rows directly
```

Keeping display integration outside the main Nu module means scripts can import the command without automatically changing their global display hook.

## Development

CI targets Nushell 0.115.1 and Windows PowerShell integration. The suite covers:

- native flat output, direct child lists, and serialization;
- explicit `table` readability without nested child records;
- direct R3CLI rendering in a real pseudo-terminal REPL;
- filtered-result tree reconstruction and orphan promotion;
- hierarchy-safe `sort-by` rendering with transformed sibling order;
- `$ans.last` redisplay of original and filtered trees;
- fallback after transformations that remove required tree fields;
- preservation of Nushell's normal display hook;
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
