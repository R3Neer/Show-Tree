<#
.SYNOPSIS
Displays a size-aware filesystem tree.

.DESCRIPTION
Displays one or more filesystem trees with logical sizes, optional file
rendering, depth limiting, minimum-size filtering and empty-folder hiding.

.PARAMETER Path
Starting path or paths. Defaults to the current directory.

.PARAMETER Dereference
Uses target metadata when sizing symbolic links.

.PARAMETER Long
Includes files in the rendered tree.

.PARAMETER Exclude
Excludes matching file paths.

.PARAMETER MaxDepth
Limits directory recursion. Zero means the root only.

.PARAMETER MinSize
Excludes files smaller than this logical size.

.PARAMETER All
Includes dot-prefixed entries.

.PARAMETER HideEmptyFolders
Hides directories containing no included files.

.PARAMETER Help
Displays R3CLI help and skips traversal.
#>

[CmdletBinding()]
param (
    [Parameter(Position = 0, ValueFromRemainingArguments = $true)]
    [Alias("p")]
    [string[]]$Path = @("."),

    [Alias("r")]
    [switch]$Dereference,

    [Alias("l")]
    [switch]$Long,

    [Alias("x")]
    [string]$Exclude,

    [Alias("d")]
    [Nullable[int]]$MaxDepth = $null,

    [Alias("m")]
    [Nullable[long]]$MinSize = $null,

    [Alias("a")]
    [switch]$All,

    [Alias("e")]
    [switch]$HideEmptyFolders,

    [Alias("h")]
    [switch]$Help
)

$r3cliPath = Join-Path $PSScriptRoot 'vendor/R3CLI/powershell/R3CLI.psd1'

if (-not (Test-Path -LiteralPath $r3cliPath)) {
    throw "Vendored R3CLI PowerShell dependency was not found at '$r3cliPath'. Reinstall Show-Tree."
}

Import-Module $r3cliPath -ErrorAction Stop

$ui = New-R3Console -Colour auto -Invocation $MyInvocation

function New-ShowTreeHelpCatalogue {
    [PSCustomObject]@{
        Product = "Show-Tree"
        Version = "0.1.1"
        Description = "Displays a size-aware filesystem tree with depth, size and visibility filtering."
        Invocation = "show-tree"
        Groups = @()
        Commands = @()
        Usage = @(
            "show-tree [path ...] [options]"
        )
        GlobalItems = @(
            [PSCustomObject]@{ Label = "path"; Description = "Starting path(s). Defaults to the current directory." },
            [PSCustomObject]@{ Label = "-r, --deref / -Dereference"; Description = "Use target metadata for symbolic-link sizes." },
            [PSCustomObject]@{ Label = "-l, --long / -Long"; Description = "Include files in the rendered tree." },
            [PSCustomObject]@{ Label = "-x, --exclude / -Exclude"; Description = "Exclude matching file paths." },
            [PSCustomObject]@{ Label = "-d, --max-depth / -MaxDepth"; Description = "Limit directory recursion. Zero means root only." },
            [PSCustomObject]@{ Label = "-m, --min-size / -MinSize"; Description = "Exclude files below this logical size." },
            [PSCustomObject]@{ Label = "-a, --all / -All"; Description = "Include dot-prefixed entries." },
            [PSCustomObject]@{ Label = "-e, --hide-empty-folders / -HideEmptyFolders"; Description = "Hide directories with no included files." },
            [PSCustomObject]@{ Label = "-h, --help / -Help"; Description = "Show this help and skip traversal." }
        )
        Notes = @(
            "Long controls rendering only; traversal still gathers files to calculate sizes and empty folders."
        )
        Examples = @(
            "show-tree",
            "show-tree . -d 2",
            "show-tree . -l -e"
        )
        HelpOptions = @("-h", "--help")
    }
}

function Format-TreeSize {
    param ([long]$Bytes)

    $culture = [Globalization.CultureInfo]::InvariantCulture

    if ($Bytes -ge 1TB) {
        return "$(([double]$Bytes / 1TB).ToString('F2', $culture)) TiB"
    }
    if ($Bytes -ge 1GB) {
        return "$(([double]$Bytes / 1GB).ToString('F2', $culture)) GiB"
    }
    if ($Bytes -ge 1MB) {
        return "$(([double]$Bytes / 1MB).ToString('F2', $culture)) MiB"
    }
    if ($Bytes -ge 1KB) {
        return "$(([double]$Bytes / 1KB).ToString('F2', $culture)) KiB"
    }

    return "$Bytes B"
}

function Test-IsDotHidden {
    param ([string]$Name)
    return $Name.StartsWith(".")
}

function Test-IsLink {
    param ($Item)
    return (
        $null -ne $Item.PSObject.Properties["LinkType"] -and
        $null -ne $Item.LinkType
    )
}

function Get-LogicalFileSize {
    param (
        $Item,
        [switch]$Dereference
    )

    $isLink = Test-IsLink $Item

    if (-not $isLink) {
        if ($null -ne $Item.PSObject.Properties["Length"]) {
            return [long]$Item.Length
        }
        return 0L
    }

    if (-not $Dereference) {
        if (
            $null -ne $Item.PSObject.Properties["Length"] -and
            $null -ne $Item.Length
        ) {
            return [long]$Item.Length
        }
        return 0L
    }

    try {
        $target = $Item.ResolveLinkTarget($true)
        if ($target -is [System.IO.FileInfo]) {
            return [long]$target.Length
        }
        return 0L
    }
    catch {
        return 0L
    }
}

function Test-Excluded {
    param (
        $Item,
        [System.Management.Automation.WildcardPattern]$Pattern
    )

    if ($null -eq $Pattern) {
        return $false
    }

    $fullName = $Item.FullName.Replace("\", "/")
    return (
        $Pattern.IsMatch($Item.Name) -or
        $Pattern.IsMatch($fullName)
    )
}

function Get-FolderNode {
    param (
        [string]$Path,
        [Nullable[int]]$MaxDepth,
        [Nullable[long]]$MinSize,
        [System.Management.Automation.WildcardPattern]$ExcludePattern,
        [switch]$All,
        [switch]$Dereference,
        [int]$DepthLevel = 0
    )

    $children = [Collections.Generic.List[object]]::new()
    $totalSize = 0L
    $hasFiles = $false

    $items = @(
        Get-ChildItem -LiteralPath $Path -Force -ErrorAction SilentlyContinue
    )

    foreach ($item in $items) {
        if (-not $All -and (Test-IsDotHidden $item.Name)) {
            continue
        }

        $isLink = Test-IsLink $item

        # Directory links are sized as link entries and are never traversed.
        if ($item.PSIsContainer -and -not $isLink) {
            $canDescend = (
                $null -eq $MaxDepth -or
                $DepthLevel -lt $MaxDepth
            )

            if (-not $canDescend) {
                continue
            }

            $childFolder = Get-FolderNode `
                -Path $item.FullName `
                -MaxDepth $MaxDepth `
                -MinSize $MinSize `
                -ExcludePattern $ExcludePattern `
                -All:$All `
                -Dereference:$Dereference `
                -DepthLevel ($DepthLevel + 1)

            $totalSize += $childFolder.SizeBytes

            if ($childFolder.HasFiles) {
                $hasFiles = $true
            }

            [void]$children.Add($childFolder)
            continue
        }

        if (Test-Excluded $item $ExcludePattern) {
            continue
        }

        $size = Get-LogicalFileSize -Item $item -Dereference:$Dereference

        if ($null -ne $MinSize -and $size -lt $MinSize) {
            continue
        }

        $fileNode = [PSCustomObject]@{
            Kind = "File"
            Name = $item.Name
            FullName = $item.FullName
            SizeBytes = $size
            HasFiles = $true
            Children = @()
        }

        $totalSize += $size
        $hasFiles = $true
        [void]$children.Add($fileNode)
    }

    $sortedChildren = @(
        $children |
            Sort-Object `
                @{ Expression = { if ($_.Kind -eq "Folder") { 0 } else { 1 } } },
                @{ Expression = { $_.Name.ToLowerInvariant() } }
    )

    $directory = Get-Item -LiteralPath $Path -Force -ErrorAction Stop

    return [PSCustomObject]@{
        Kind = "Folder"
        Name = $directory.Name
        FullName = $directory.FullName
        SizeBytes = $totalSize
        HasFiles = $hasFiles
        Children = $sortedChildren
    }
}

function Get-RootNodes {
    param (
        [string[]]$Paths,
        [Nullable[int]]$MaxDepth,
        [Nullable[long]]$MinSize,
        [System.Management.Automation.WildcardPattern]$ExcludePattern,
        [switch]$All,
        [switch]$Dereference
    )

    $roots = [Collections.Generic.List[object]]::new()

    foreach ($rawPath in $Paths) {
        $isPattern = [System.Management.Automation.WildcardPattern]::ContainsWildcardCharacters($rawPath)

        if ($isPattern) {
            $resolvedPaths = @(Resolve-Path -Path $rawPath -ErrorAction SilentlyContinue)
        }
        else {
            try {
                $resolvedPaths = @(Resolve-Path -LiteralPath $rawPath -ErrorAction Stop)
            }
            catch {
                throw (
                    Format-R3Diagnostic `
                        -Message "Path '$rawPath' was not found" `
                        -Code "ShowTree.Path.NotFound"
                )
            }
        }

        foreach ($resolvedPath in $resolvedPaths) {
            $item = Get-Item -LiteralPath $resolvedPath.ProviderPath -Force -ErrorAction Stop

            if ($isPattern -and -not $All -and (Test-IsDotHidden $item.Name)) {
                continue
            }

            $isLink = Test-IsLink $item

            if ($item.PSIsContainer -and -not $isLink) {
                [void]$roots.Add(
                    (Get-FolderNode `
                        -Path $item.FullName `
                        -MaxDepth $MaxDepth `
                        -MinSize $MinSize `
                        -ExcludePattern $ExcludePattern `
                        -All:$All `
                        -Dereference:$Dereference)
                )
                continue
            }

            $size = Get-LogicalFileSize -Item $item -Dereference:$Dereference

            [void]$roots.Add(
                [PSCustomObject]@{
                    Kind = "File"
                    Name = $item.Name
                    FullName = $item.FullName
                    SizeBytes = $size
                    HasFiles = $true
                    Children = @()
                }
            )
        }
    }

    return @(
        $roots |
            Sort-Object @{ Expression = { $_.FullName.ToLowerInvariant() } }
    )
}

function Get-VisibleChildren {
    param (
        $Node,
        [switch]$Long,
        [switch]$HideEmptyFolders
    )

    foreach ($child in $Node.Children) {
        if ($child.Kind -eq "Folder") {
            if ($HideEmptyFolders -and -not $child.HasFiles) {
                continue
            }
            $child
            continue
        }

        if ($Long) {
            $child
        }
    }
}

function Get-TreePrefix {
    param (
        [bool[]]$AncestorLast,
        [bool]$IsLast
    )

    $prefix = ""

    foreach ($ancestorIsLast in $AncestorLast) {
        $prefix += if ($ancestorIsLast) { "    " } else { "│   " }
    }

    $prefix += if ($IsLast) { "└── " } else { "├── " }
    return $prefix
}

function Write-TreeNodeLine {
    param (
        $Console,
        $Node,
        [string]$Prefix,
        [switch]$Root
    )

    $label = if ($Root) { $Node.FullName } else { $Node.Name }
    $sizeText = Format-TreeSize $Node.SizeBytes

    if ($Node.Kind -eq "Folder") {
        Write-R3Line $Console @(
            @{ Text = $Prefix; Role = "secondary" },
            @{ Text = $label; Role = "heading"; Bold = $true },
            @{ Text = " [Folder] "; Role = "secondary" },
            @{ Text = "($sizeText)"; Role = "value" }
        )
        return
    }

    Write-R3Line $Console @(
        @{ Text = $Prefix; Role = "secondary" },
        @{ Text = $label; Role = "accent" },
        @{ Text = " ($sizeText)"; Role = "secondary" }
    )
}

function Write-TreeChildren {
    param (
        $Console,
        $Node,
        [switch]$Long,
        [switch]$HideEmptyFolders,
        [bool[]]$AncestorLast = @()
    )

    $children = @(
        Get-VisibleChildren `
            -Node $Node `
            -Long:$Long `
            -HideEmptyFolders:$HideEmptyFolders
    )

    for ($i = 0; $i -lt $children.Count; $i++) {
        $child = $children[$i]
        $isLast = $i -eq ($children.Count - 1)

        $prefix = Get-TreePrefix -AncestorLast $AncestorLast -IsLast $isLast

        Write-TreeNodeLine -Console $Console -Node $child -Prefix $prefix

        if ($child.Kind -eq "Folder") {
            Write-TreeChildren `
                -Console $Console `
                -Node $child `
                -Long:$Long `
                -HideEmptyFolders:$HideEmptyFolders `
                -AncestorLast @($AncestorLast + $isLast)
        }
    }
}

if ($Help) {
    Write-R3Help $ui (New-ShowTreeHelpCatalogue)
    return
}

if ($null -ne $MaxDepth -and $MaxDepth -lt 0) {
    throw (
        Format-R3Diagnostic `
            -Message "MaxDepth cannot be negative" `
            -Code "ShowTree.MaxDepth.Invalid"
    )
}

if ($null -ne $MinSize -and $MinSize -lt 0) {
    throw (
        Format-R3Diagnostic `
            -Message "MinSize cannot be negative" `
            -Code "ShowTree.MinSize.Invalid"
    )
}

$excludePattern = if ([string]::IsNullOrWhiteSpace($Exclude)) {
    $null
}
else {
    [System.Management.Automation.WildcardPattern]::new(
        $Exclude.Replace("\", "/"),
        [System.Management.Automation.WildcardOptions]::IgnoreCase
    )
}

$roots = @(
    Get-RootNodes `
        -Paths $Path `
        -MaxDepth $MaxDepth `
        -MinSize $MinSize `
        -ExcludePattern $excludePattern `
        -All:$All `
        -Dereference:$Dereference
)

Write-R3Banner $ui "SHOW-TREE"

if ($roots.Count -eq 0) {
    Write-R3Status $ui warning "No matching paths."
    return
}

for ($i = 0; $i -lt $roots.Count; $i++) {
    $root = $roots[$i]

    if ($i -gt 0) {
        Write-R3Line $ui
    }

    Write-TreeNodeLine -Console $ui -Node $root -Prefix "" -Root

    if ($root.Kind -eq "Folder") {
        Write-TreeChildren `
            -Console $ui `
            -Node $root `
            -Long:$Long `
            -HideEmptyFolders:$HideEmptyFolders
    }
}

$grandTotal = ($roots | Measure-Object -Property SizeBytes -Sum).Sum

Write-R3Line $ui
Write-R3KeyValue $ui "Total size" (Format-TreeSize ([long]$grandTotal))