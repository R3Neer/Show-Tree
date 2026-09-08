"""Apply the self-contained dependency and REPL-output integration changes.

Temporary migration helper for the feature branch. It removes itself and the
bootstrap workflow after producing the final source tree.
"""
from __future__ import annotations

from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]


def replace_once(path: Path, old: str, new: str) -> None:
    text = path.read_text(encoding="utf-8")
    if text.count(old) != 1:
        raise SystemExit(f"Expected exactly one match in {path}: {old[:80]!r}")
    path.write_text(text.replace(old, new, 1), encoding="utf-8", newline="\n")


# Nushell: consume the private vendored adapter and always return native data.
nu_path = ROOT / "show-tree.nu"
replace_once(
    nu_path,
    "const R3CLI_MODULE = (path self ../R3CLI/dist/nushell/r3cli)",
    "const R3CLI_MODULE = (path self vendor/R3CLI/nushell/r3cli)",
)
replace_once(
    nu_path,
    "        'Interactive calls render the R3CLI tree. Redirected or captured calls return native Nushell records.'",
    "        'Every call returns native Nushell records. Direct interactive calls also render the R3CLI tree.'",
)
old_main_tail = """    if $redirected {
        return (
            $roots
            | each {|root| to-pipeline-node $root $long $hide_empty_folders }
        )
    }

    let ui = (r3cli console --colour auto)
    r3cli banner $ui 'SHOW-TREE'

    if ($roots | is-empty) {
        r3cli status $ui warning 'No matching paths.'
        return
    }

    for row in ($roots | enumerate) {
        let root = $row.item

        if $row.index > 0 {
            r3cli line $ui
        }

        render-node-line $ui $root '' true

        if $root.kind == 'Folder' {
            render-tree-children $ui $root $long $hide_empty_folders []
        }
    }

    let total = (
        $roots
        | reduce --fold 0 {|root, acc| $acc + $root.size_bytes }
    )

    r3cli line $ui
    r3cli key-value $ui 'Total size' (format-tree-size $total)
"""
new_main_tail = """    let result = (
        $roots
        | each {|root| to-pipeline-node $root $long $hide_empty_folders }
    )

    if not $redirected {
        let ui = (r3cli console --colour auto)
        r3cli banner $ui 'SHOW-TREE'

        if ($roots | is-empty) {
            r3cli status $ui warning 'No matching paths.'
        } else {
            for row in ($roots | enumerate) {
                let root = $row.item

                if $row.index > 0 {
                    r3cli line $ui
                }

                render-node-line $ui $root '' true

                if $root.kind == 'Folder' {
                    render-tree-children $ui $root $long $hide_empty_folders []
                }
            }

            let total = (
                $roots
                | reduce --fold 0 {|root, acc| $acc + $root.size_bytes }
            )

            r3cli line $ui
            r3cli key-value $ui 'Total size' (format-tree-size $total)
        }
    }

    if $redirected {
        $result
    } else {
        # The installer adds a display_output hook that consumes this marker.
        # The value still reaches Nushell's result machinery, including $ans.last,
        # without being rendered a second time as an automatic table.
        $result | metadata set {|| merge { show_tree_pre_rendered: true } }
    }
"""
replace_once(nu_path, old_main_tail, new_main_tail)

# PowerShell: use the private vendored adapter rather than a sibling checkout.
ps_path = ROOT / "Show-Tree.ps1"
ps_text = ps_path.read_text(encoding="utf-8")
ps_text, count = re.subn(
    r"\$r3cliPath = Join-Path `\n    \(Split-Path -Parent \$PSScriptRoot\) `\n    'R3CLI\\dist\\powershell\\R3CLI\\R3CLI\.psd1'\n\nif \(-not \(Test-Path -LiteralPath \$r3cliPath\)\) \{\n    throw \"R3CLI PowerShell distribution was not found at '\$r3cliPath'\. Keep R3CLI and Show-Tree as sibling repositories\.\"\n\}",
    "$r3cliPath = Join-Path $PSScriptRoot 'vendor\\R3CLI\\powershell\\R3CLI.psd1'\n\nif (-not (Test-Path -LiteralPath $r3cliPath)) {\n    throw \"Vendored R3CLI PowerShell dependency was not found at '$r3cliPath'. Reinstall Show-Tree.\"\n}",
    ps_text,
    count=1,
)
if count != 1:
    raise SystemExit("Could not replace the PowerShell R3CLI path block.")
ps_path.write_text(ps_text, encoding="utf-8", newline="\n")

# Installer: verify the vendored dependency and install only Show-Tree itself.
installer = ROOT / "Install-ShowTree.ps1"
installer_text = installer.read_text(encoding="utf-8")
start = installer_text.index("$showTreeRoot = $PSScriptRoot")
end = installer_text.index("function Set-MarkedBlock {")
new_bootstrap = r'''$showTreeRoot = $PSScriptRoot
$showTreePowerShell = Join-Path $showTreeRoot 'Show-Tree.ps1'
$showTreeNushell = Join-Path $showTreeRoot 'show-tree.nu'
$dependencyManifest = Join-Path $showTreeRoot 'dependencies.json'
$r3cliPowerShellRoot = Join-Path $showTreeRoot 'vendor\R3CLI\powershell'
$r3cliNushellRoot = Join-Path $showTreeRoot 'vendor\R3CLI\nushell\r3cli'
$r3cliPowerShell = Join-Path $r3cliPowerShellRoot 'R3CLI.psd1'

foreach ($requiredPath in @($showTreePowerShell, $showTreeNushell, $dependencyManifest)) {
    if (-not (Test-Path -LiteralPath $requiredPath)) {
        throw "Required Show-Tree file was not found: '$requiredPath'."
    }
}

$dependencies = Get-Content -LiteralPath $dependencyManifest -Raw | ConvertFrom-Json -AsHashtable
$r3cli = $dependencies['R3CLI']
if ($null -eq $r3cli) {
    throw "dependencies.json does not contain the R3CLI dependency."
}

function Test-VendoredFiles {
    param (
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][Collections.IDictionary]$Files,
        [Parameter(Mandatory)][string]$Label
    )

    foreach ($entry in $Files.GetEnumerator()) {
        $path = Join-Path $Root $entry.Key
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            throw "Vendored R3CLI $Label file is missing: '$path'. Reinstall Show-Tree."
        }
        $actual = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
        if ($actual -ne $entry.Value) {
            throw "Vendored R3CLI $Label file failed SHA256 verification: '$path'. Reinstall Show-Tree."
        }
    }
}

Test-VendoredFiles -Root $r3cliPowerShellRoot -Files $r3cli['powershell']['files'] -Label 'PowerShell'
Test-VendoredFiles -Root $r3cliNushellRoot -Files $r3cli['nushell']['files'] -Label 'Nushell'

$r3cliVersion = [string]$r3cli['version']
$r3cliRevision = [string]$r3cli['revision']

'''
installer_text = installer_text[:start] + new_bootstrap + installer_text[end:]

old_profile = r'''$nuProfileBlock = @(
    "# >>> Show-Tree >>>"
    "use '$nuScriptPath' [main show-tree-help tree]"
    ""
    "def help [...rest: string] {"
    "    if ((`$rest | length) == 1) and ((`$rest | first) == 'show-tree') {"
    "        show-tree-help"
    "    } else {"
    "        %help ...`$rest"
    "    }"
    "}"
    "# <<< Show-Tree <<<"
) -join [Environment]::NewLine'''
new_profile = r'''$nuProfileBlock = @(
    "# >>> Show-Tree >>>"
    "use '$nuScriptPath' [main show-tree-help tree]"
    ""
    "def help [...rest: string] {"
    "    if ((`$rest | length) == 1) and ((`$rest | first) == 'show-tree') {"
    "        show-tree-help"
    "    } else {"
    "        %help ...`$rest"
    "    }"
    "}"
    ""
    "# Preserve the user's existing display hook. Show-Tree marks values that it"
    "# has already rendered so Nushell stores them for `$ans.last without also"
    "# drawing the same native records as an automatic table."
    "let show_tree_previous_display_output = (`$env.config.hooks.display_output? | default null)"
    "`$env.config.hooks.display_output = {"
    "    metadata access {|meta|"
    "        if (((`$meta | get --optional show_tree_pre_rendered) | default false) == true) {"
    "            `$in | ignore"
    "        } else if `$show_tree_previous_display_output == null {"
    "            `$in | table"
    "        } else {"
    "            `$in | do `$show_tree_previous_display_output"
    "        }"
    "    }"
    "}"
    "# <<< Show-Tree <<<"
) -join [Environment]::NewLine'''
if installer_text.count(old_profile) != 1:
    raise SystemExit("Could not find the Nushell profile block.")
installer_text = installer_text.replace(old_profile, new_profile, 1)
installer_text = installer_text.replace(
    'Write-Host "R3CLI shell adapters rebuilt from: $r3cliRoot"',
    'Write-Host "R3CLI dependency verified: $r3cliVersion ($r3cliRevision)"',
    1,
)
installer.write_text(installer_text, encoding="utf-8", newline="\n")

# README: document native return values, $ans and self-contained installation.
readme = ROOT / "README.md"
readme.write_text(r'''# Show-Tree

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

- A direct interactive call renders the normal R3CLI tree and returns the native value with metadata marking it as already rendered. The installer adds a `display_output` hook that suppresses only that duplicate automatic table while preserving any display hook the user already had.
- Piped, redirected, captured and subexpression calls return the same native values without rendering the R3CLI tree.

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

Clone or download Show-Tree and run its installer:

```powershell
.\Install-ShowTree.ps1
```

The installer verifies the bundled R3CLI dependency against `dependencies.json`, updates the PowerShell all-hosts profile, imports the Nushell commands from `config.nu`, installs the Nushell display hook described above, and shadows the legacy Windows `tree` command with a warning before forwarding to `tree.com`.

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
''', encoding="utf-8", newline="\n")

# Test config for a real REPL/pseudo-terminal check of display suppression + $ans.
(ROOT / "tests" / "Nushell.ReplConfig.nu").write_text(r'''$env.config.max_last_result_size = 1mb

const SHOW_TREE = (path self ../show-tree.nu)
use $SHOW_TREE [main]

let show_tree_previous_display_output = ($env.config.hooks.display_output? | default null)
$env.config.hooks.display_output = {
    metadata access {|meta|
        if ((($meta | get --optional show_tree_pre_rendered) | default false) == true) {
            $in | ignore
        } else if $show_tree_previous_display_output == null {
            $in | table
        } else {
            $in | do $show_tree_previous_display_output
        }
    }
}
''', encoding="utf-8", newline="\n")

# Final CI no longer checks out R3CLI: passing tests prove the repository is
# self-contained for users.
(ROOT / ".github" / "workflows" / "test.yml").write_text(r'''name: Test

on:
  push:
  pull_request:

jobs:
  nushell-structured-output:
    runs-on: ubuntu-latest
    steps:
      - name: Check out Show-Tree
        uses: actions/checkout@v5
        with:
          path: Show-Tree

      - name: Set up Nushell
        uses: hustcer/setup-nu@v3
        with:
          version: '0.115.1'

      - name: Test native pipeline output
        run: nu Show-Tree/tests/Nushell.Structured.nu

      - name: Test direct rendering path
        run: nu --no-config-file -c 'use Show-Tree/show-tree.nu [main]; show-tree Show-Tree -d 0 | ignore'

      - name: Test direct REPL result through ans
        shell: bash
        run: |
          cat > /tmp/show-tree-input <<'EOF'
          show-tree Show-Tree -d 0
          $ans.last.0.type | save --force /tmp/show-tree-ans.txt
          exit
          EOF
          script -qec "nu --config Show-Tree/tests/Nushell.ReplConfig.nu" /tmp/show-tree-transcript.txt < /tmp/show-tree-input
          test "$(cat /tmp/show-tree-ans.txt)" = "dir"
          grep -q "SHOW-TREE" /tmp/show-tree-transcript.txt
          if grep -q "╭" /tmp/show-tree-transcript.txt; then
            echo "Direct Show-Tree output was rendered again as a Nushell table."
            exit 1
          fi

  windows-installation:
    runs-on: windows-latest
    steps:
      - name: Check out Show-Tree
        uses: actions/checkout@v5
        with:
          path: Show-Tree

      - name: Set up Nushell
        uses: hustcer/setup-nu@v3
        with:
          version: '0.115.1'

      - name: Reject a corrupted vendored dependency
        shell: pwsh
        run: |
          $copy = Join-Path $env:RUNNER_TEMP 'Show-Tree-corrupt'
          Copy-Item -Recurse -Force ./Show-Tree $copy
          Add-Content -LiteralPath (Join-Path $copy 'vendor/R3CLI/powershell/resources.json') -Value ' '
          try {
              & (Join-Path $copy 'Install-ShowTree.ps1')
              throw 'Corrupt dependency was unexpectedly accepted.'
          }
          catch {
              if ($_.Exception.Message -notmatch 'SHA256 verification') { throw }
          }

      - name: Install Show-Tree
        shell: pwsh
        run: ./Show-Tree/Install-ShowTree.ps1

      - name: Validate Nushell profile import and structured output
        shell: pwsh
        run: |
          $nuConfig = (& nu --no-config-file -c 'print --no-newline $nu.config-path' | Out-String).Trim()
          nu --config $nuConfig -c 'show-tree Show-Tree -d 0 | get 0.type | print'

      - name: Validate PowerShell profile import
        shell: pwsh
        run: pwsh -Command 'Show-Tree Show-Tree -MaxDepth 0'
''', encoding="utf-8", newline="\n")

# Remove one-shot branch bootstrap machinery. The permanent dependency updater
# remains in scripts/update_r3cli.py for maintainers.
for temporary in (
    ROOT / ".github" / "workflows" / "bootstrap-vendor.yml",
    ROOT / ".github" / "workflows" / "apply-feature.yml",
    Path(__file__),
):
    if temporary.exists():
        temporary.unlink()
