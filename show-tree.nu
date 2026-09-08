const R3CLI_MODULE = (path self vendor/R3CLI/nushell/r3cli)
use $R3CLI_MODULE

const HELP_CATALOGUE = {
    product: 'Show-Tree'
    version: '0.1.0'
    description: 'Displays a size-aware filesystem tree with depth, size and visibility filtering.'
    invocation: 'show-tree'
    groups: []
    commands: []
    usage: [
        'show-tree [path ...] [options]'
    ]
    'global-items': [
        { label: 'path', description: 'Starting path(s). Defaults to the current directory.' }
        { label: '-r, --deref / -Dereference', description: 'Use target metadata for symbolic-link sizes.' }
        { label: '-l, --long / -Long', description: 'Include file nodes in rendered and structured trees.' }
        { label: '-x, --exclude / -Exclude', description: 'Exclude matching file paths.' }
        { label: '-d, --max-depth / -MaxDepth', description: 'Limit directory recursion. Zero means root only.' }
        { label: '-m, --min-size / -MinSize', description: 'Exclude files below this logical size.' }
        { label: '-a, --all / -All', description: 'Include dot-prefixed entries.' }
        { label: '-e, --hide-empty-folders / -HideEmptyFolders', description: 'Hide directories with no included files.' }
        { label: '-h, --help / -Help', description: 'Show this help and skip traversal.' }
    ]
    notes: [
        'Every call returns native Nushell records. Direct interactive calls also render the R3CLI tree.'
        'Long controls file-node visibility; traversal still gathers files to calculate sizes and empty folders.'
    ]
    examples: [
        'show-tree'
        'show-tree . -d 2'
        'show-tree . -l -e'
        'show-tree . -d 2 | to json'
    ]
    'help-options': ['-h' '--help']
}

export def show-tree-help [] {
    let ui = (r3cli console --colour auto)
    r3cli help $ui $HELP_CATALOGUE
}

def format-tree-size [bytes: int] {
    if $bytes >= 1099511627776 {
        return $"((($bytes | into float) / 1099511627776.0) | into string --decimals 2) TiB"
    }
    if $bytes >= 1073741824 {
        return $"((($bytes | into float) / 1073741824.0) | into string --decimals 2) GiB"
    }
    if $bytes >= 1048576 {
        return $"((($bytes | into float) / 1048576.0) | into string --decimals 2) MiB"
    }
    if $bytes >= 1024 {
        return $"((($bytes | into float) / 1024.0) | into string --decimals 2) KiB"
    }

    $"($bytes) B"
}

def run-du [
    paths: list<any>
    deref: bool
    all: bool
    exclude: any
    max_depth: any
    min_size: any
] {
    # An explicit absolute cwd keeps du on the same path-resolution code path as explicit user paths.
    let actual_paths = if ($paths | is-empty) { [(pwd)] } else { $paths }
    let min_bytes = if $min_size == null { null } else { $min_size | into int }

    if $exclude == null {
        if $max_depth == null {
            if $min_bytes == null {
                return (%du ...$actual_paths --long --deref=$deref --all=$all)
            }
            return (%du ...$actual_paths --long --deref=$deref --all=$all --min-size $min_bytes)
        }

        if $min_bytes == null {
            return (%du ...$actual_paths --long --deref=$deref --all=$all --max-depth $max_depth)
        }

        return (%du ...$actual_paths --long --deref=$deref --all=$all --max-depth $max_depth --min-size $min_bytes)
    }

    if $max_depth == null {
        if $min_bytes == null {
            return (%du ...$actual_paths --long --deref=$deref --all=$all --exclude $exclude)
        }
        return (%du ...$actual_paths --long --deref=$deref --all=$all --exclude $exclude --min-size $min_bytes)
    }

    if $min_bytes == null {
        return (%du ...$actual_paths --long --deref=$deref --all=$all --exclude $exclude --max-depth $max_depth)
    }

    %du ...$actual_paths --long --deref=$deref --all=$all --exclude $exclude --max-depth $max_depth --min-size $min_bytes
}

def normalize-du-node [
    entry: record
    all: bool
] {
    let full_path = ($entry.path | path expand)
    let path_kind = ($full_path | path type)

    if $path_kind != 'dir' {
        return {
            kind: 'File'
            name: ($full_path | path basename)
            full_name: $full_path
            size_bytes: ($entry.apparent | into int)
            has_files: true
            children: []
        }
    }

    let raw_directories = ($entry | get --optional directories | default [])
    let raw_files = ($entry | get --optional files | default [])

    let directories = (
        $raw_directories
        | where {|child|
            $all or (not (($child.path | path basename) | str starts-with '.'))
        }
        | each {|child| normalize-du-node $child $all }
        | sort-by name --ignore-case
    )

    let files = (
        $raw_files
        | where {|child|
            $all or (not (($child.path | path basename) | str starts-with '.'))
        }
        | each {|child| normalize-du-node $child $all }
        | sort-by name --ignore-case
    )

    let children = ($directories ++ $files)

    # Nu du includes directory-entry metadata in apparent totals; Show-Tree's contract does not.
    let size_bytes = (
        $children
        | reduce --fold 0 {|child, acc| $acc + $child.size_bytes }
    )

    let has_files = ($children | any {|child| $child.has_files })

    {
        kind: 'Folder'
        name: ($full_path | path basename)
        full_name: $full_path
        size_bytes: $size_bytes
        has_files: $has_files
        children: $children
    }
}

def visible-children [
    node: record
    long: bool
    hide_empty_folders: bool
] {
    $node.children
    | where {|child|
        if $child.kind == 'Folder' {
            (not $hide_empty_folders) or $child.has_files
        } else {
            $long
        }
    }
}

def to-pipeline-node [
    node: record
    long: bool
    hide_empty_folders: bool
] {
    let children = if $node.kind == 'Folder' {
        visible-children $node $long $hide_empty_folders
        | each {|child| to-pipeline-node $child $long $hide_empty_folders }
    } else {
        []
    }

    {
        name: $node.name
        type: (if $node.kind == 'Folder' { 'dir' } else { 'file' })
        path: $node.full_name
        size: ($node.size_bytes | into filesize)
        children: $children
    }
}

def tree-prefix [
    ancestor_last: list<bool>
    is_last: bool
] {
    let prefix = (
        $ancestor_last
        | each {|ancestor_is_last|
            if $ancestor_is_last { '    ' } else { '│   ' }
        }
        | str join ''
    )

    $prefix + (if $is_last { '└── ' } else { '├── ' })
}

def render-node-line [
    ui: record
    node: record
    prefix: string
    root: bool
] {
    let label = if $root { $node.full_name } else { $node.name }
    let size_text = (format-tree-size $node.size_bytes)

    if $node.kind == 'Folder' {
        r3cli line $ui [
            { text: $prefix, role: 'secondary' }
            { text: $label, role: 'heading', bold: true }
            { text: ' [Folder] ', role: 'secondary' }
            { text: ('(' + $size_text + ')'), role: 'value' }
        ]
        return
    }

    r3cli line $ui [
        { text: $prefix, role: 'secondary' }
        { text: $label, role: 'accent' }
        { text: (' (' + $size_text + ')'), role: 'secondary' }
    ]
}

def render-tree-children [
    ui: record
    node: record
    long: bool
    hide_empty_folders: bool
    ancestor_last: list<bool>
] {
    let children = (visible-children $node $long $hide_empty_folders)

    for row in ($children | enumerate) {
        let child = $row.item
        let is_last = ($row.index == (($children | length) - 1))
        let prefix = (tree-prefix $ancestor_last $is_last)

        render-node-line $ui $child $prefix false

        if $child.kind == 'Folder' {
            render-tree-children $ui $child $long $hide_empty_folders ([...$ancestor_last $is_last])
        }
    }
}

# Long changes node visibility only; the backend always requests du --long to obtain structured children.
export def main [
    --deref (-r)
    --long (-l)
    --exclude (-x): glob
    --max-depth (-d): int
    --min-size (-m): filesize
    --all (-a)
    --hide-empty-folders (-e)
    ...path: glob
] {
    let redirected = (is-redirected)

    if $max_depth != null and $max_depth < 0 {
        error make { msg: 'MaxDepth cannot be negative.' }
    }

    if $min_size != null and ($min_size | into int) < 0 {
        error make { msg: 'MinSize cannot be negative.' }
    }

    let raw = (run-du $path $deref $all $exclude $max_depth $min_size)

    let roots = (
        $raw
        | each {|entry| normalize-du-node $entry $all }
        | sort-by full_name --ignore-case
    )

    let result = (
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
}

export def --wrapped tree [...rest: string] {
    let ui = (r3cli console --colour auto)
    r3cli status $ui warning "Use 'show-tree' for size-aware tree output."
    ^tree.com ...$rest
}
