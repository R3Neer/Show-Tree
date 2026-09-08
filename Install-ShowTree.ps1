[CmdletBinding()]
param ()

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$showTreeRoot = $PSScriptRoot
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

function Set-MarkedBlock {
    param (
        [string]$Path,
        [string]$StartMarker,
        [string]$EndMarker,
        [string]$Block
    )

    $parent = Split-Path -Parent $Path

    if (-not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }

    $existing = if (Test-Path -LiteralPath $Path) {
        Get-Content -LiteralPath $Path -Raw
    }
    else {
        ""
    }

    $pattern = (
        "(?ms)" +
        [regex]::Escape($StartMarker) +
        ".*?" +
        [regex]::Escape($EndMarker) +
        "\r?\n?"
    )

    $clean = [regex]::Replace($existing, $pattern, "").TrimEnd()

    $newContent = if ([string]::IsNullOrWhiteSpace($clean)) {
        $Block.Trim() + [Environment]::NewLine
    }
    else {
        $clean +
        [Environment]::NewLine +
        [Environment]::NewLine +
        $Block.Trim() +
        [Environment]::NewLine
    }

    Set-Content -LiteralPath $Path -Value $newContent -Encoding utf8NoBOM
}

$escapedPowerShell = $showTreePowerShell.Replace("'", "''")
$escapedR3cli = $r3cliPowerShell.Replace("'", "''")

$powerShellProfileBlock = @(
    "# >>> Show-Tree >>>"
    "function Show-Tree {"
    "    & '$escapedPowerShell' @args"
    "}"
    ""
    "function tree {"
    "    Import-Module '$escapedR3cli' -ErrorAction Stop"
    "    `$ui = New-R3Console -Colour auto"
    "    Write-R3Status `$ui warning `"Use 'Show-Tree' for size-aware tree output.`""
    "    & `"`$env:SystemRoot\System32\tree.com`" @args"
    "}"
    "# <<< Show-Tree <<<"
) -join [Environment]::NewLine

$powerShellProfile = $PROFILE.CurrentUserAllHosts

Set-MarkedBlock `
    -Path $powerShellProfile `
    -StartMarker "# >>> Show-Tree >>>" `
    -EndMarker "# <<< Show-Tree <<<" `
    -Block $powerShellProfileBlock

Set-Item `
    -Path Function:\global:Show-Tree `
    -Value ([scriptblock]::Create("& '$escapedPowerShell' @args"))

$treeBody = @(
    "Import-Module '$escapedR3cli' -ErrorAction Stop"
    '$ui = New-R3Console -Colour auto'
    'Write-R3Status $ui warning "Use ''Show-Tree'' for size-aware tree output."'
    '& "$env:SystemRoot\System32\tree.com" @args'
) -join [Environment]::NewLine

Set-Item `
    -Path Function:\global:tree `
    -Value ([scriptblock]::Create($treeBody))

$nu = Get-Command nu -ErrorAction SilentlyContinue

if ($null -eq $nu) {
    throw "Nushell was not found in PATH."
}

# Do not load the user's existing Nu configuration while locating config.nu.
# A stale Show-Tree import is exactly the kind of broken config this installer
# needs to be able to repair after the repository has moved.
$nuConfigPath = (
    & $nu.Source --no-config-file -c 'print --no-newline $nu.config-path' |
        Out-String
).Trim()

if ([string]::IsNullOrWhiteSpace($nuConfigPath)) {
    throw "Nushell did not report a config path."
}

$nuScriptPath = $showTreeNushell.Replace("\", "/").Replace("'", "''")

# This wrapper preserves Nu's normal help everywhere except Show-Tree, whose help is rendered by R3CLI.
# display_output accepts a string, closure or null. String hooks must remain source strings so Nushell itself
# evaluates them as hooks; closures can be delegated to directly.
$nuProfileBlock = @(
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
    "let show_tree_previous_display_type = (`$show_tree_previous_display_output | describe)"
    ""
    "if `$show_tree_previous_display_type == 'string' {"
    "    let show_tree_wrapped_display_source = ("
    "        'metadata access {|meta| if (((`$meta | get --optional show_tree_pre_rendered) | default false) == true) { `$in | ignore } else { `$in | do { '"
    "        + `$show_tree_previous_display_output"
    "        + ' } } }'"
    "    )"
    "    `$env.config.hooks.display_output = `$show_tree_wrapped_display_source"
    "} else {"
    "    `$env.config.hooks.display_output = {"
    "        metadata access {|meta|"
    "            if (((`$meta | get --optional show_tree_pre_rendered) | default false) == true) {"
    "                `$in | ignore"
    "            } else if `$show_tree_previous_display_output == null {"
    "                `$in | table"
    "            } else {"
    "                `$in | do `$show_tree_previous_display_output"
    "            }"
    "        }"
    "    }"
    "}"
    "# <<< Show-Tree <<<"
) -join [Environment]::NewLine

Set-MarkedBlock `
    -Path $nuConfigPath `
    -StartMarker "# >>> Show-Tree >>>" `
    -EndMarker "# <<< Show-Tree <<<" `
    -Block $nuProfileBlock

Write-Host "R3CLI dependency verified: $r3cliVersion ($r3cliRevision)"
Write-Host "PowerShell profile updated: $powerShellProfile"
Write-Host "Nushell config updated: $nuConfigPath"
Write-Host "Show-Tree is available immediately in this PowerShell session."
