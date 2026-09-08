[CmdletBinding()]
param ()

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$showTreeRoot = $PSScriptRoot
$toolsRoot = Split-Path -Parent $showTreeRoot
$r3cliRoot = Join-Path $toolsRoot 'R3CLI'

$showTreePowerShell = Join-Path $showTreeRoot 'Show-Tree.ps1'
$showTreeNushell = Join-Path $showTreeRoot 'show-tree.nu'
$r3cliPowerShell = Join-Path $r3cliRoot 'dist\powershell\R3CLI\R3CLI.psd1'
$r3cliNushell = Join-Path $r3cliRoot 'dist\nushell\r3cli'
$r3cliPowerShellBuild = Join-Path $r3cliRoot 'scripts\build_powershell.py'
$r3cliNushellBuild = Join-Path $r3cliRoot 'scripts\build_nushell.py'

$requiredSourcePaths = @(
    $showTreePowerShell,
    $showTreeNushell,
    $r3cliPowerShellBuild,
    $r3cliNushellBuild
)

foreach ($requiredPath in $requiredSourcePaths) {
    if (-not (Test-Path -LiteralPath $requiredPath)) {
        throw (
            "Required source file was not found: '$requiredPath'. " +
            "Keep Show-Tree and R3CLI as sibling repositories under the same parent directory."
        )
    }
}

function Get-PythonInvocation {
    $python = Get-Command python -ErrorAction SilentlyContinue
    if ($null -ne $python) {
        return [PSCustomObject]@{
            Command = $python.Source
            Prefix = @()
        }
    }

    $py = Get-Command py -ErrorAction SilentlyContinue
    if ($null -ne $py) {
        return [PSCustomObject]@{
            Command = $py.Source
            Prefix = @('-3')
        }
    }

    throw "Python 3.11 or newer is required to build the R3CLI shell adapters."
}

function Invoke-R3CliBuild {
    param (
        [Parameter(Mandatory)]
        [string]$Script,

        [Parameter(Mandatory)]
        [string]$Output
    )

    $python = Get-PythonInvocation
    $arguments = @($python.Prefix) + @($Script, '--output', $Output)

    & $python.Command @arguments
    if ($LASTEXITCODE -ne 0) {
        throw "R3CLI build failed: '$Script'."
    }
}

# R3CLI distributions are generated artifacts rather than committed files.
# Rebuilding them here makes a fresh pair of sibling clones installable directly
# and ensures a reinstall consumes the currently checked-out R3CLI sources.
Invoke-R3CliBuild -Script $r3cliNushellBuild -Output $r3cliNushell
Invoke-R3CliBuild -Script $r3cliPowerShellBuild -Output (Split-Path -Parent $r3cliPowerShell)

$requiredBuiltPaths = @(
    $r3cliPowerShell,
    (Join-Path $r3cliNushell 'mod.nu')
)

foreach ($requiredPath in $requiredBuiltPaths) {
    if (-not (Test-Path -LiteralPath $requiredPath)) {
        throw "R3CLI build did not produce the required file: '$requiredPath'."
    }
}

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
# needs to be able to repair after the repositories have moved.
$nuConfigPath = (
    & $nu.Source --no-config-file -c 'print --no-newline $nu.config-path' |
        Out-String
).Trim()

if ([string]::IsNullOrWhiteSpace($nuConfigPath)) {
    throw "Nushell did not report a config path."
}

$nuScriptPath = $showTreeNushell.Replace("\", "/").Replace("'", "''")

# This wrapper preserves Nu's normal help everywhere except Show-Tree, whose help is rendered by R3CLI.
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
    "# <<< Show-Tree <<<"
) -join [Environment]::NewLine

Set-MarkedBlock `
    -Path $nuConfigPath `
    -StartMarker "# >>> Show-Tree >>>" `
    -EndMarker "# <<< Show-Tree <<<" `
    -Block $nuProfileBlock

Write-Host "R3CLI shell adapters rebuilt from: $r3cliRoot"
Write-Host "PowerShell profile updated: $powerShellProfile"
Write-Host "Nushell config updated: $nuConfigPath"
Write-Host "Show-Tree is available immediately in this PowerShell session."
