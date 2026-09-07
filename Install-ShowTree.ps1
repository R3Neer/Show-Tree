[CmdletBinding()]
param ()

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$showTreePowerShell = 'D:\OneDrive\Documentos Samuel\Herramientas software\Show-Tree\Show-Tree.ps1'
$showTreeNushell = 'D:/OneDrive/Documentos Samuel/Herramientas software/Show-Tree/show-tree.nu'
$r3cliPowerShell = 'D:\OneDrive\Documentos Samuel\Herramientas software\R3CLI\dist\powershell\R3CLI\R3CLI.psd1'

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

$nuConfigPath = (
    & $nu.Source -c 'print --no-newline $nu.config-path' |
        Out-String
).Trim()

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

Write-Host "PowerShell profile updated: $powerShellProfile"
Write-Host "Nushell config updated: $nuConfigPath"
Write-Host "Show-Tree is available immediately in this PowerShell session."
