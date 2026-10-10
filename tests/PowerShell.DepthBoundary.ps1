$ErrorActionPreference = 'Stop'
$temporaryRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
$fixture = Join-Path $temporaryRoot ("show-tree-depth-" + [guid]::NewGuid().ToString('N'))
$fixture = [IO.Path]::GetFullPath($fixture)
if (-not $fixture.StartsWith($temporaryRoot, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Fixture escaped the temporary directory.'
}
$script = Join-Path $PSScriptRoot '..\src\powershell\Show-Tree.ps1'
$previousFixture = $env:SHOW_TREE_DEPTH_FIXTURE
function Get-TreeText {
    param([string]$Path = $fixture, [hashtable]$Options = @{})
    @(& $script $Path @Options 6>&1 | ForEach-Object {
        if ($_ -is [System.Management.Automation.InformationRecord]) { [string]$_.MessageData } else { [string]$_ }
    }) -join [Environment]::NewLine
}
try {
    foreach ($relative in @('a\b\c', 'empty', 'empty-chain\e1\e2', '空 carpeta [1]', '.dot', 'attribute-hidden', 'zero', 'hidden-only\.hidden-child')) {
        [IO.Directory]::CreateDirectory((Join-Path $fixture $relative)) | Out-Null
    }
    $files = @{
        'root.txt' = 3; 'a\level1.txt' = 5; 'a\b\level2.txt' = 7; 'a\b\c\deep.txt' = 11
        '空 carpeta [1]\odd.txt' = 17; '.dot\hidden.txt' = 13; 'attribute-hidden\hidden.txt' = 15
        'zero\zero.txt' = 0; 'hidden-only\.hidden-child\hidden.txt' = 0
    }
    foreach ($relative in $files.Keys) {
        [IO.File]::WriteAllBytes((Join-Path $fixture $relative), [byte[]]::new($files[$relative]))
    }
    (Get-Item -LiteralPath (Join-Path $fixture 'attribute-hidden')).Attributes = [IO.FileAttributes]::Directory -bor [IO.FileAttributes]::Hidden
    $env:SHOW_TREE_DEPTH_FIXTURE = $fixture
    # Nushell tests run before they save artifacts into the fixture. Remove only
    # those explicitly named test outputs before PowerShell size assertions.
    & nu --no-config-file (Join-Path $PSScriptRoot 'Nushell.DepthBoundary.nu')
    if ($LASTEXITCODE -ne 0) { throw 'Nushell depth-boundary tests failed.' }
    Remove-Item -LiteralPath (Join-Path $fixture 'snapshot.showtree'), (Join-Path $fixture 'tree-output.txt')
    for ($depth = 0; $depth -le 3; $depth++) {
        $text = Get-TreeText -Options @{ MaxDepth = $depth }
        $expected = @(3, 25, 32, 43)[$depth]
        $mark = if ($depth -lt 3) { '≥ ' } else { '' }
        if ($text -notmatch "Total size\s+$mark$expected B") { throw "Wrong total at depth ${depth}: $text" }
        if ($depth -lt 3) {
            $name = @('a', 'b', 'c')[$depth]
            if ($text -notmatch "📁 $name \(≥ 0 B\)") { throw "Boundary folder missing at depth $depth" }
        }
        if ($text -match '\.dot|attribute-hidden') { throw 'Hidden boundary folder exposed.' }
        $short = Get-TreeText -Options @{ MaxDepth = $depth; Short = $true }
        if ($short -match '\.txt' -or $short -notmatch "Total size\s+$mark$expected B") { throw 'Short changed accounting.' }
        $empty = Get-TreeText -Options @{ MaxDepth = $depth; HideEmptyFolders = $true }
        if (($depth -eq 0) -ne ($empty -match '📁 empty \(')) { throw 'Unknown/known empty distinction failed.' }
        if ($depth -ge 1 -and $empty -notmatch '📁 zero \(0 B\)') { throw 'Zero-byte file folder incorrectly hidden.' }
        Write-Host "PowerShell depth $depth verified: $mark$expected B"
    }
    $full = Get-TreeText
    if ($full -match '≥' -or $full -notmatch 'Total size\s+43 B') { throw 'Unlimited traversal not complete.' }
    $all = Get-TreeText -Options @{ MaxDepth = 0; All = $true }
    if ($all -notmatch '\.dot \(≥ 0 B\)' -or $all -notmatch 'attribute-hidden \(≥ 0 B\)') { throw 'All lost boundary folders.' }
    $allFull = Get-TreeText -Options @{ All = $true }
    if ($allFull -match '≥' -or $allFull -notmatch 'Total size\s+71 B') { throw 'All total incorrect.' }
    $leaf = Get-TreeText -Path (Join-Path $fixture 'a\b\c') -Options @{ MaxDepth = 0 }
    if ($leaf -match '≥' -or $leaf -notmatch 'Total size\s+11 B') { throw 'Leaf without subfolders incorrectly incomplete.' }
    $hiddenOnly = Get-TreeText -Path (Join-Path $fixture 'hidden-only') -Options @{ MaxDepth = 0 }
    if ($hiddenOnly -match '≥' -or $hiddenOnly -notmatch 'Total size\s+0 B') { throw 'Invisible folders affected completeness.' }
    $min = Get-TreeText -Options @{ MaxDepth = 1; MinSize = 8 }
    if ($min -notmatch 'Total size\s+≥ 17 B') { throw 'MinSize changed partial accounting.' }
    $exclude = Get-TreeText -Options @{ MaxDepth = 1; Exclude = '*.txt' }
    if ($exclude -notmatch 'Total size\s+≥ 0 B') { throw 'Exclude lost incompleteness.' }
    $file = Get-TreeText -Path (Join-Path $fixture 'root.txt') -Options @{ MaxDepth = 0 }
    if ($file -match '≥' -or $file -notmatch 'Total size\s+3 B') { throw 'File root incorrectly incomplete.' }
    $multi = @(& $script @((Join-Path $fixture 'root.txt'), (Join-Path $fixture 'a')) -MaxDepth 0 6>&1 | ForEach-Object { [string]$_ }) -join "`n"
    if ($multi -notmatch 'Total size\s+≥ 8 B') { throw 'Multiple root completeness lost.' }
    $rejected = $false
    try { Get-TreeText -Options @{ MaxDepth = -1 } | Out-Null } catch { $rejected = $true }
    if (-not $rejected) { throw 'Negative depth accepted.' }
    $rounding = Join-Path $fixture 'rounding'
    [IO.Directory]::CreateDirectory((Join-Path $rounding 'unvisited-empty')) | Out-Null
    [IO.File]::WriteAllBytes((Join-Path $rounding 'rounding.txt'), [byte[]]::new(2047))
    $rounded = Get-TreeText -Path $rounding -Options @{ MaxDepth = 0 }
    if ($rounded -notmatch 'Total size\s+≥ 1.99 KiB' -or $rounded -notmatch '\(≥ 1.99 KiB\)') { throw 'Lower bound rounded upward.' }
    Write-Host 'PowerShell 7 depth-boundary tests passed.'
} finally {
    $env:SHOW_TREE_DEPTH_FIXTURE = $previousFixture
    # Native deletion only, with the absolute target rechecked before recursion.
    $resolvedFixture = [IO.Path]::GetFullPath($fixture)
    if ($resolvedFixture.StartsWith($temporaryRoot, [StringComparison]::OrdinalIgnoreCase) -and
        ([IO.Path]::GetFileName($resolvedFixture) -like 'show-tree-depth-*')) {
        if (Test-Path -LiteralPath $resolvedFixture) { Remove-Item -LiteralPath $resolvedFixture -Recurse -Force }
        Write-Host "Temporary fixture removed: $resolvedFixture"
    } else { throw 'Refusing to remove an unexpected fixture path.' }
}
