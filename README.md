# Show-Tree

A size-aware filesystem tree for PowerShell and Nushell, rendered with [R3CLI](https://github.com/R3Neer/R3CLI).

The PowerShell implementation traverses the filesystem directly. The Nushell implementation delegates traversal and filtering to Nushell's structured `du --long` output and only normalizes and renders the result.

## Behaviour

Both implementations share the same runtime contract:

- Sizes are logical file bytes. Directory-entry metadata is not counted.
- `MaxDepth` / `--max-depth` limits traversal and therefore affects totals.
- `MinSize` / `--min-size` excludes files from both the tree and totals.
- `Long` / `--long` controls whether individual files are rendered.
- `HideEmptyFolders` / `--hide-empty-folders` hides directories containing no included files.
- `All` / `--all` includes dot-prefixed entries.
- Directories are rendered before files, with case-insensitive name ordering.
- Directory symbolic links are not recursively traversed.

## Options

| Behaviour | PowerShell | Nushell |
| --- | --- | --- |
| Starting paths | `Path` / positional | positional |
| Dereference links | `-Dereference`, `-r` | `--deref`, `-r` |
| Show files | `-Long`, `-l` | `--long`, `-l` |
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
```

## Installation

This checkout is configured for the following sibling layout:

```text
D:\OneDrive\Documentos Samuel\Herramientas software\
├── R3CLI\
└── Show-Tree\
```

Run:

```powershell
.\Install-ShowTree.ps1
```

The installer adds `Show-Tree` to the PowerShell all-hosts profile, imports the Nushell commands from `config.nu`, and shadows the legacy Windows `tree` command with a warning before forwarding to `tree.com`.

## Requirements

- PowerShell 7
- Nushell 0.115+
- R3CLI built for both PowerShell and Nushell
- Windows for the legacy `tree.com` forwarding wrapper
