$ErrorActionPreference = 'Stop'

$fixture = Join-Path $env:RUNNER_TEMP 'show-tree-default-complete-ps'
$deep = Join-Path $fixture 'a\b\c'

Remove-Item -LiteralPath $fixture -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Path $deep -Force | Out-Null
Set-Content -LiteralPath (Join-Path $fixture 'root.txt') -Value 'root' -NoNewline
Set-Content -LiteralPath (Join-Path $fixture '.hidden.txt') -Value 'hidden' -NoNewline
Set-Content -LiteralPath (Join-Path $deep 'deep.txt') -Value 'deep' -NoNewline

$script = Join-Path $PSScriptRoot '..\src\powershell\Show-Tree.ps1'

# A direct invocation should show the hidden-entry reminder when -All is absent.
# R3CLI warning status uses PowerShell's warning stream, so redirect stream 3 only
# for this assertion.
$direct = @(& $script $fixture 3>&1 6>&1)
$directText = ($direct | ForEach-Object { [string]$_ }) -join [Environment]::NewLine

if ($directText -notmatch 'Hidden entries are omitted') { throw 'Interactive PowerShell output did not show the hidden-entry reminder.' }

# Piped output is the representation that may be saved to a file. It must contain
# only the tree, not the interactive reminder.
$output = @(
    & $script $fixture 6>&1 | ForEach-Object {
        if ($_ -is [System.Management.Automation.InformationRecord]) {
            [string]$_.MessageData
        } else {
            [string]$_
        }
    }
)
$text = $output -join [Environment]::NewLine

if ($text -notmatch 'root\.txt') { throw 'Default PowerShell Show-Tree omitted a visible root file.' }
if ($text -match '\.hidden\.txt') { throw 'Default PowerShell Show-Tree should omit dot-prefixed files.' }
if ($text -notmatch 'deep\.txt') { throw 'Default PowerShell Show-Tree did not recurse deeply enough.' }
if ($text -match 'Hidden entries are omitted') { throw 'Piped PowerShell output leaked the interactive hidden-entry reminder.' }

$all = @(
    & $script $fixture -All 6>&1 | ForEach-Object {
        if ($_ -is [System.Management.Automation.InformationRecord]) { [string]$_.MessageData } else { [string]$_ }
    }
) -join [Environment]::NewLine

if ($all -notmatch '\.hidden\.txt') { throw '-All did not include the dot-prefixed file.' }

$short = @(
    & $script $fixture -Short 6>&1 | ForEach-Object {
        if ($_ -is [System.Management.Automation.InformationRecord]) { [string]$_.MessageData } else { [string]$_ }
    }
) -join [Environment]::NewLine

if ($short -match 'root\.txt' -or $short -match 'deep\.txt') { throw '-Short should suppress file rows.' }
if ($short -notmatch 'a' -or $short -notmatch 'b' -or $short -notmatch 'c') { throw '-Short lost the recursive directory chain.' }

$limited = @(
    & $script $fixture -MaxDepth 1 6>&1 | ForEach-Object {
        if ($_ -is [System.Management.Automation.InformationRecord]) {
            [string]$_.MessageData
        } else {
            [string]$_
        }
    }
) -join [Environment]::NewLine

if ($limited -match 'deep\.txt') { throw '-MaxDepth stopped limiting traversal.' }

Remove-Item -LiteralPath $fixture -Recurse -Force
Write-Host 'PowerShell default/all/short/notice tests passed.'
