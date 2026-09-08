# Show-Tree

A size-aware filesystem tree for PowerShell and Nushell, rendered with [R3CLI](https://github.com/R3Neer/R3CLI).

Show-Tree is self-contained for users: the exact R3CLI PowerShell and Nushell adapters it needs are vendored as a private dependency. A separate R3CLI checkout, Python, or dependency build is not required to install or run Show-Tree.

The PowerShell implementation traverses the filesystem directly. The Nushell implementation delegates traversal and filtering to Nushell's structured `du --long` output, then normalizes the result for both interactive rendering and native pipeline use.

## Behaviour

Both implementations share the same filesystem contract:

- Sizes are logical file bytes. Directory-entry metadata is not counted.
- `MaxDepth` / `--max-depth` limits traversal and therefore affects totals.
- `MinSize` / `--min-size` excludes files from both the tree and totals.
- `Long` / `--long` controls whether individual file nodes are exposed.
- `HideEmptyFolders` / `--hide-empty-folders` hides directories containing no included files.
- `All` / `--all` includes dot-prefixed entries.
- Directories are ordered before files, with case-insensitive name ordering.
- Directory symbolic links are not recursively traversed.

## Nushell values and display

`show-tree` always returns native Nushell values. Presentation depends on the destination:

- A direct interactive call renders the normal R3CLI tree and returns the native value with metadata marking it as already rendered. The installed display integration suppresses only that duplicate automatic table while preserving the previous display hook.
- Piped, redirected, captured and subexpression calls return the same native values without rendering the R3CLI tree.

The display integration lives in the repository file `show-tree-display.nu`; the installer no longer injects the full hook implementation into the user's `config.nu`.

Each returned node has this shape:

```nu
{
    name: string
    type: 'dir' | 'file'
    path: string
    size: filesize
    children: list
}
```

Directory nodes contain visible child nodes recursively. File nodes use an empty `children` list. Without `--long`, file nodes are omitted while their sizes still contribute to directory totals.

Normal pipelines therefore work directly:

```nu
show-tree D:/Projects --max-depth 2 | get name

let tree = (show-tree D:/Projects --max-depth 3 --long)
$tree.0.children

show-tree D:/Projects --max-depth 3 --long
| to json
| save --force project-tree.json
```

A direct REPL call also remains available through Nushell's `$ans.last` when `max_last_result_size` is enabled in the user's Nushell configuration:

```nu
show-tree D:/Projects -d 2
$ans.last.0.children
```

No dedicated JSON mode is needed. Callers can use `to json`, `to nuon`, `to yaml`, filters, projections, or any other normal Nushell operation.

## Options

| Behaviour | PowerShell | Nushell |
| --- | --- | --- |
| Starting paths | `Path` / positional | positional |
| Dereference links | `-Dereference`, `-r` | `--deref`, `-r` |
| Show file nodes | `-Long`, `-l` | `--long`, `-l` |
| Exclude files | `-Exclude`, `-x` | `--exclude`, `-x` |
| Maximum depth | `-MaxDepth`, `-d` | `--max-depth`, `-d` |
| Minimum size | `-MinSize`, `-m` | `--min-size`, `-m` |
| Dot-prefixed entries | `-All`, `-a` | `--all`, `-a` |
| Hide empty folders | `-HideEmptyFolders`, `-e` | `--hide-empty-folders`, `-e` |
| Help | `-Help`, `-h` | `--help`, `-h` |

## Examples

PowerShell:

```powershell
Show-Tree
Show-Tree D:\Projects -MaxDepth 2
Show-Tree -Long -MinSize 10MB -HideEmptyFolders
Show-Tree -Exclude "*.tmp"
```

Nushell:

```nu
show-tree
show-tree D:/Projects --max-depth 2
show-tree --long --min-size 10MiB --hide-empty-folders
show-tree --exclude '*.tmp'
show-tree D:/Projects -d 2 | to json
```

## Installation

For PowerShell and Nushell together:

```powershell
.\Install-ShowTree.ps1
```

For Nushell only:

```nu
nu --no-config-file ./install-show-tree.nu
```

Using `--no-config-file` is intentional: it lets the installer repair a broken previous Show-Tree block even when the current `config.nu` cannot be loaded.

The PowerShell installer also supports shell-specific operation:

```powershell
.\Install-ShowTree.ps1 -PowerShellOnly
.\Install-ShowTree.ps1 -NushellOnly
```

The installer verifies the bundled R3CLI dependency against `dependencies.json`. Nushell config updates are upgrade-safe: an existing marked Show-Tree block is replaced in place rather than removed and appended elsewhere, the complete candidate config is checked with `nu-check` before writing, and the previous config is backed up as `config.nu.show-tree.bak`. Ambiguous or mismatched Show-Tree markers cause the installer to stop without modifying the file.

The dependency is private to Show-Tree. It is loaded from `vendor/R3CLI` and never requires an R3CLI repository beside Show-Tree or an R3CLI installation on `PSModulePath`.

## Updating R3CLI for maintainers

R3CLI updates are explicit development work, following the same vendoring model used by ModpackTools. From a Show-Tree checkout, point the update helper at a clean R3CLI checkout:

```console
python scripts/update_r3cli.py <clean-R3CLI-checkout>
```

The helper refuses a dirty R3CLI checkout by default, builds both official shell adapters, replaces only the generated `vendor/R3CLI` destinations, and records the exact revision, version and SHA256 hashes in `dependencies.json`. Python is needed for this maintainer operation only, not for users installing Show-Tree.

## Requirements

- PowerShell 7 for the PowerShell command and installer
- Nushell 0.115+ for the Nushell command
- Windows for the installer and legacy `tree.com` forwarding wrapper

R3CLI is already bundled as a verified private dependency.
