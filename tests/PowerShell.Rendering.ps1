$ErrorActionPreference = 'Stop'

$fixture = Join-Path $env:RUNNER_TEMP 'show-tree-folder-glyph-ps'
$child = Join-Path $fixture 'src'

Remove-Item -LiteralPath $fixture -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Path $child -Force | Out-Null
Set-Content -LiteralPath (Join-Path $child 'main.txt') -Value 'x' -NoNewline

$script = Join-Path $PSScriptRoot '..\src\powershell\Show-Tree.ps1'
$text = @(
    & $script $fixture -All 6>&1 | ForEach-Object {
        if ($_ -is [System.Management.Automation.InformationRecord]) {
            [string]$_.MessageData
        } else {
            [string]$_
        }
    }
) -join [Environment]::NewLine

if ($text -notmatch '📁') { throw 'PowerShell tree is missing the folder glyph.' }
if ($text -notmatch '📁 .*src') { throw 'Child folder glyph was not rendered before its label.' }
if ($text -match '\[Folder\]') { throw 'Legacy [Folder] label is still present.' }
if ($text -notmatch 'main\.txt') { throw 'File rendering changed unexpectedly.' }

Remove-Item -LiteralPath $fixture -Recurse -Force
Write-Host 'PowerShell folder-glyph rendering test passed.'
