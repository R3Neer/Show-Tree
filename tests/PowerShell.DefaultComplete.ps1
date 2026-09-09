$ErrorActionPreference = 'Stop'

$fixture = Join-Path $env:RUNNER_TEMP 'show-tree-default-complete-ps'
$deep = Join-Path $fixture 'a\b\c'

Remove-Item -LiteralPath $fixture -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Path $deep -Force | Out-Null
Set-Content -LiteralPath (Join-Path $fixture 'root.txt') -Value 'root' -NoNewline
Set-Content -LiteralPath (Join-Path $fixture '.hidden.txt') -Value 'hidden' -NoNewline
Set-Content -LiteralPath (Join-Path $deep 'deep.txt') -Value 'deep' -NoNewline

$script = Join-Path $PSScriptRoot '..\src\powershell\Show-Tree.ps1'
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

if ($text -notmatch 'root\.txt') { throw 'Default PowerShell Show-Tree omitted a root file.' }
if ($text -notmatch '\.hidden\.txt') { throw 'Default PowerShell Show-Tree omitted a dot-prefixed file.' }
if ($text -notmatch 'deep\.txt') { throw 'Default PowerShell Show-Tree did not recurse deeply enough.' }
if ($text -notmatch 'a' -or $text -notmatch 'b' -or $text -notmatch 'c') { throw 'Default PowerShell Show-Tree lost the recursive directory chain.' }

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
Write-Host 'PowerShell complete-default tests passed.'
