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
        { label: '-l, --long / -Long', description: 'Include file rows in rendered and structured trees.' }
        { label: '-x, --exclude / -Exclude', description: 'Exclude matching file paths.' }
        { label: '-d, --max-depth / -MaxDepth', description: 'Limit directory recursion. Zero means root only.' }
        { label: '-m, --min-size / -MinSize', description: 'Exclude files below this logical size.' }
        { label: '-a, --all / -All', description: 'Include dot-prefixed entries.' }
        { label: '-e, --hide-empty-folders / -HideEmptyFolders', description: 'Hide directories with no included files.' }
        { label: '-h, --help / -Help', description: 'Show this help and skip traversal.' }
    ]
    notes: [
        'Nushell output is a flat native table: tree, name, type, size, depth and path.'
        'Direct interactive results are rendered as the R3CLI tree by the installed display integration.'
        'Pipe to table, to json, where, sort-by or any other Nushell command to work with the rows directly.'
        'Long controls file-row visibility; traversal still gathers files to calculate sizes and empty folders.'
    ]
    examples: [
        'show-tree'
        'show-tree . -d 2'
        'show-tree . -l -e'
        'show-tree . -d 2 | table'
        'show-tree . -d 2 | to json'
    ]
    'help-options': ['-h' '--help']
}

export def show-tree-help [] {
    let ui = (r3cli console --colour auto)
    r3cli help $ui $HELP_CATALOGUE
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

def display-name [node: record]: nothing -> string {
    let candidate = ($node.name | default '' | into string)
    if ($candidate | str trim) == '' { $node.full_name } else { $candidate }
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

def to-table-row [
    node: record
    tree_label: string
    depth: int
]: nothing -> record {
    {
        tree: $tree_label
        name: (display-name $node)
        type: (if $node.kind == 'Folder' { 'dir' } else { 'file' })
        size: ($node.size_bytes | into filesize)
        depth: $depth
        path: $node.full_name
    }
}

def flatten-child [
    node: record
    long: bool
    hide_empty_folders: bool
    ancestor_last: list<bool>
    is_last: bool
    depth: int
]: nothing -> list<record> {
    let prefix = (tree-prefix $ancestor_last $is_last)
    let row = (to-table-row $node ($prefix + (display-name $node)) $depth)

    if $node.kind != 'Folder' {
        return [$row]
    }

    let children = (visible-children $node $long $hide_empty_folders)
    let descendants = (
        $children
        | enumerate
        | each {|item|
            let child_is_last = ($item.index == (($children | length) - 1))
            flatten-child $item.item $long $hide_empty_folders ([...$ancestor_last $is_last]) $child_is_last ($depth + 1)
        }
        | reduce --fold [] {|part, acc| $acc ++ $part }
    )

    [$row ...$descendants]
}

def flatten-root [
    root: record
    long: bool
    hide_empty_folders: bool
]: nothing -> list<record> {
    let row = (to-table-row $root $root.full_name 0)

    if $root.kind != 'Folder' {
        return [$row]
    }

    let children = (visible-children $root $long $hide_empty_folders)
    let descendants = (
        $children
        | enumerate
        | each {|item|
            let child_is_last = ($item.index == (($children | length) - 1))
            flatten-child $item.item $long $hide_empty_folders [] $child_is_last 1
        }
        | reduce --fold [] {|part, acc| $acc ++ $part }
    )

    [$row ...$descendants]
}

# Long changes row visibility only; the backend always requests du --long to obtain structured children.
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
        | each {|root| flatten-root $root $long $hide_empty_folders }
        | reduce --fold [] {|part, acc| $acc ++ $part }
    )

    if $redirected {
        $result
    } else {
        # The display integration recognizes this metadata and renders the native
        # rows as the R3CLI tree. Because the command itself prints nothing, the
        # same native value can later be displayed again through $ans.last.
        $result | metadata set {|| merge { show_tree_result: true } }
    }
}

export def --wrapped tree [...rest: string] {
    let ui = (r3cli console --colour auto)
    r3cli status $ui warning "Use 'show-tree' for size-aware tree output."
    ^tree.com ...$rest
}
