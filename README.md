# Show-Tree

A size-aware filesystem tree for PowerShell and Nushell, rendered with [R3CLI](https://github.com/R3Neer/R3CLI).

The PowerShell implementation traverses the filesystem directly. The Nushell implementation delegates traversal and filtering to Nushell's structured `du --long` output, then normalizes the result for either interactive rendering or native pipeline use.

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

## Nushell pipelines

`show-tree` adapts to how it is called:

- At the end of an interactive command line, it renders the normal R3CLI tree.
- When its result is piped, redirected, captured in a variable, or used in a subexpression, it returns native Nushell records and does not render the visual tree.

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

Directory nodes contain their visible child nodes recursively. File nodes use an empty `children` list. Without `--long`, file nodes are omitted from the structured tree just as they are from the interactive tree, while their sizes still contribute to directory totals.

That means normal Nushell pipelines work directly:

```nu
show-tree D:/Projects --max-depth 2 | get name

let tree = (show-tree D:/Projects --max-depth 3 --long)
$tree.0.children

show-tree D:/Projects --max-depth 3 --long
| to json
| save --force project-tree.json

show-tree D:/Projects --max-depth 3
| to nuon
| save --force project-tree.nuon
```

No separate JSON mode is required: the command returns Nushell values, so callers can choose `to json`, `to nuon`, `to yaml`, filtering, projection, or any other pipeline operation themselves.

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

Show-Tree and R3CLI are expected to be sibling repositories. Their parent directory can be anywhere:

```text
<tools-root>\
├── R3CLI\
└── Show-Tree\
```

For example:

```text
D:\Tools\
├── R3CLI\
└── Show-Tree\
```

Run the installer from the Show-Tree checkout:

```powershell
.\Install-ShowTree.ps1
```

The installer discovers both repositories from its own location, rebuilds the deterministic R3CLI PowerShell and Nushell distributions from the sibling checkout, updates the PowerShell all-hosts profile, imports the Nushell commands from `config.nu`, and shadows the legacy Windows `tree` command with a warning before forwarding to `tree.com`.

The installer asks Nushell for its configuration path with configuration loading disabled, so it can repair a stale Show-Tree import after the repositories have been moved. The Show-Tree implementations resolve R3CLI relative to their own checkout rather than embedding a machine-specific path.

## Requirements

- PowerShell 7
- Nushell 0.115+
- Python 3.11+ at installation time to build the R3CLI shell distributions
- Show-Tree and R3CLI checked out as sibling directories
- Windows for the installer and legacy `tree.com` forwarding wrapper
