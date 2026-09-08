[CmdletBinding()]
param (
    [switch]$PowerShellOnly,
    [switch]$NushellOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if ($PowerShellOnly -and $NushellOnly) {
    throw "PowerShellOnly and NushellOnly cannot be used together."
}

$installPowerShell = -not $NushellOnly
$installNushell = -not $PowerShellOnly

$showTreeRoot = $PSScriptRoot
$showTreePowerShell = Join-Path $showTreeRoot 'Show-Tree.ps1'
$showTreeNushell = Join-Path $showTreeRoot 'show-tree.nu'
$showTreeDisplay = Join-Path $showTreeRoot 'show-tree-display.nu'
$dependencyManifest = Join-Path $showTreeRoot 'dependencies.json'
$r3cliPowerShellRoot = Join-Path $showTreeRoot 'vendor\R3CLI\powershell'
$r3cliNushellRoot = Join-Path $showTreeRoot 'vendor\R3CLI\nushell\r3cli'
$r3cliPowerShell = Join-Path $r3cliPowerShellRoot 'R3CLI.psd1'

$requiredPaths = @($dependencyManifest)
if ($installPowerShell) { $requiredPaths += $showTreePowerShell }
if ($installNushell) { $requiredPaths += @($showTreeNushell, $showTreeDisplay) }

foreach ($requiredPath in $requiredPaths) {
    if (-not (Test-Path -LiteralPath $requiredPath -PathType Leaf)) {
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

if ($installPowerShell) {
    Test-VendoredFiles -Root $r3cliPowerShellRoot -Files $r3cli['powershell']['files'] -Label 'PowerShell'
}
if ($installNushell) {
    Test-VendoredFiles -Root $r3cliNushellRoot -Files $r3cli['nushell']['files'] -Label 'Nushell'
}

$r3cliVersion = [string]$r3cli['version']
$r3cliRevision = [string]$r3cli['revision']

function Get-MarkedBlockCandidate {
    param (
        [Parameter(Mandatory)][AllowEmptyString()][string]$Existing,
        [Parameter(Mandatory)][string]$StartMarker,
        [Parameter(Mandatory)][string]$EndMarker,
        [Parameter(Mandatory)][string]$Block
    )

    $startMatches = [regex]::Matches($Existing, [regex]::Escape($StartMarker))
    $endMatches = [regex]::Matches($Existing, [regex]::Escape($EndMarker))

    if ($startMatches.Count -eq 0 -and $endMatches.Count -eq 0) {
        $clean = $Existing.TrimEnd()
        if ([string]::IsNullOrWhiteSpace($clean)) {
            return $Block.Trim() + [Environment]::NewLine
        }

        return (
            $clean +
            [Environment]::NewLine +
            [Environment]::NewLine +
            $Block.Trim() +
            [Environment]::NewLine
        )
    }

    if ($startMatches.Count -ne 1 -or $endMatches.Count -ne 1) {
        throw (
            "Refusing to modify the file because the Show-Tree markers are ambiguous. " +
            "Found $($startMatches.Count) start marker(s) and $($endMatches.Count) end marker(s)."
        )
    }

    $pattern = (
        "(?s)" +
        [regex]::Escape($StartMarker) +
        ".*?" +
        [regex]::Escape($EndMarker)
    )
    $match = [regex]::Match($Existing, $pattern)

    if (-not $match.Success) {
        throw "Refusing to modify the file because the Show-Tree marker order is invalid."
    }

    # Replace in place instead of removing the old block and appending a new one.
    # This preserves the ordering and semantics of the user's surrounding config.
    return (
        $Existing.Substring(0, $match.Index) +
        $Block.Trim() +
        $Existing.Substring($match.Index + $match.Length)
    )
}

function Set-MarkedBlockSafely {
    param (
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$StartMarker,
        [Parameter(Mandatory)][string]$EndMarker,
        [Parameter(Mandatory)][string]$Block
    )

    $parent = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }

    $existing = if (Test-Path -LiteralPath $Path) {
        [string](Get-Content -LiteralPath $Path -Raw)
    } else {
        ""
    }

    $candidate = Get-MarkedBlockCandidate `
        -Existing $existing `
        -StartMarker $StartMarker `
        -EndMarker $EndMarker `
        -Block $Block

    if (Test-Path -LiteralPath $Path) {
        Copy-Item -LiteralPath $Path -Destination ($Path + '.show-tree.bak') -Force
    }

    Set-Content -LiteralPath $Path -Value $candidate -Encoding utf8NoBOM -NoNewline
}

function Set-NushellConfigSafely {
    param (
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Block,
        [Parameter(Mandatory)][string]$NuExecutable
    )

    $parent = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }

    $existing = if (Test-Path -LiteralPath $Path) {
        [string](Get-Content -LiteralPath $Path -Raw)
    } else {
        ""
    }

    $candidate = Get-MarkedBlockCandidate `
        -Existing $existing `
        -StartMarker "# >>> Show-Tree >>>" `
        -EndMarker "# <<< Show-Tree <<<" `
        -Block $Block

    $candidatePath = Join-Path $parent ('.show-tree-config-' + [guid]::NewGuid().ToString('N') + '.nu')
    Set-Content -LiteralPath $candidatePath -Value $candidate -Encoding utf8NoBOM -NoNewline

    try {
        $candidateNuPath = $candidatePath.Replace("\", "/").Replace("'", "''")
        & $NuExecutable --no-config-file -c "if (open --raw '$candidateNuPath' | nu-check) { exit 0 } else { exit 1 }"
        if ($LASTEXITCODE -ne 0) {
            throw (
                "The candidate Nushell config failed syntax validation. " +
                "Your existing config.nu has not been changed."
            )
        }

        if (Test-Path -LiteralPath $Path) {
            Copy-Item -LiteralPath $Path -Destination ($Path + '.show-tree.bak') -Force
        }

        # Write only after the complete candidate has passed nu-check. A failed
        # generation or validation therefore leaves the user's config untouched.
        Move-Item -LiteralPath $candidatePath -Destination $Path -Force
    }
    finally {
        if (Test-Path -LiteralPath $candidatePath) {
            Remove-Item -LiteralPath $candidatePath -Force
        }
    }
}

if ($installPowerShell) {
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
    Set-MarkedBlockSafely `
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
}

if ($installNushell) {
    $nu = Get-Command nu -ErrorAction SilentlyContinue
    if ($null -eq $nu) {
        throw "Nushell was not found in PATH."
    }

    # Locate config.nu without loading it. This is essential for repair installs:
    # a broken previous Show-Tree block must not prevent the installer from running.
    $nuConfigPath = (
        & $nu.Source --no-config-file -c 'print --no-newline $nu.config-path' |
            Out-String
    ).Trim()

    if ([string]::IsNullOrWhiteSpace($nuConfigPath)) {
        throw "Nushell did not report a config path."
    }

    $nuScriptPath = $showTreeNushell.Replace("\", "/").Replace("'", "''")
    $nuDisplayPath = $showTreeDisplay.Replace("\", "/").Replace("'", "''")

    # Keep config.nu deliberately small. The display hook implementation lives
    # in a tested repository module rather than being injected as a large block
    # of generated Nushell source into the user's configuration file.
    $nuProfileBlock = @(
        "# >>> Show-Tree >>>"
        "use '$nuScriptPath' [main show-tree-help tree]"
        "use '$nuDisplayPath'"
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

    Set-NushellConfigSafely `
        -Path $nuConfigPath `
        -Block $nuProfileBlock `
        -NuExecutable $nu.Source
}

Write-Host "R3CLI dependency verified: $r3cliVersion ($r3cliRevision)"
if ($installPowerShell) {
    Write-Host "PowerShell profile updated: $powerShellProfile"
    Write-Host "Show-Tree is available immediately in this PowerShell session."
}
if ($installNushell) {
    Write-Host "Nushell config updated safely: $nuConfigPath"
    if (Test-Path -LiteralPath ($nuConfigPath + '.show-tree.bak')) {
        Write-Host "Nushell config backup: $($nuConfigPath + '.show-tree.bak')"
    }
    Write-Host "Open a new Nushell session to load Show-Tree."
}
