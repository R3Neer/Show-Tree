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
        'Nushell output is one flat native row per visible node: name, type, size, children and path.'
        'children is a flat list of direct child names, never nested child records.'
        'Representable filtered, sorted and sliced results keep the R3CLI tree as their automatic REPL view.'
        'Pipe explicitly to table, to json or another renderer when you want that representation instead.'
        'Long controls file-row visibility; traversal still gathers files to calculate sizes and empty folders.'
    ]
    examples: [
        'show-tree'
        'show-tree . -d 2'
        'show-tree . -l -e'
        'show-tree . -d 2 | where size > 1mb'
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

def to-lineage-row [
    node: record
    parent_path: any
    child_names: list<string>
]: nothing -> record {
    {
        name: (display-name $node)
        type: (if $node.kind == 'Folder' { 'dir' } else { 'file' })
        size: ($node.size_bytes | into filesize)
        children: $child_names
        path: $node.full_name
        parent_path: $parent_path
    }
}

def flatten-child [
    node: record
    long: bool
    hide_empty_folders: bool
    parent_path: string
]: nothing -> list<record> {
    let children = if $node.kind == 'Folder' {
        visible-children $node $long $hide_empty_folders
    } else {
        []
    }

    let child_names = ($children | each {|child| display-name $child })
    let row = (to-lineage-row $node $parent_path $child_names)

    if $node.kind != 'Folder' {
        return [$row]
    }

    let descendants = (
        $children
        | each {|child|
            flatten-child $child $long $hide_empty_folders $node.full_name
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
    let children = if $root.kind == 'Folder' {
        visible-children $root $long $hide_empty_folders
    } else {
        []
    }

    let child_names = ($children | each {|child| display-name $child })
    let row = (to-lineage-row $root null $child_names)

    if $root.kind != 'Folder' {
        return [$row]
    }

    let descendants = (
        $children
        | each {|child|
            flatten-child $child $long $hide_empty_folders $root.full_name
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

    let lineage = (
        $roots
        | each {|root| flatten-root $root $long $hide_empty_folders }
        | reduce --fold [] {|part, acc| $acc ++ $part }
    )

    # Every visible filesystem node is a first-level row. `children` contains only
    # direct child names, so explicit tables stay flat instead of nesting records.
    let result = ($lineage | select name type size children path)
    let render_lineage = $lineage

    # Presentation metadata records the original parent relation. Filters and
    # ordering commands can change the public rows while this lineage lets the REPL
    # reconstruct a truthful tree from exactly the rows that remain.
    $result | metadata set {||
        merge {
            show_tree_result: true
            show_tree_render: $render_lineage
        }
    }
}

export def --wrapped tree [...rest: string] {
    let ui = (r3cli console --colour auto)
    r3cli status $ui warning "Use 'show-tree' for size-aware tree output."
    ^tree.com ...$rest
}
