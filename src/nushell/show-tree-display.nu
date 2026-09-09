# Show-Tree display integration for Nushell sessions.
#
# Traversal and structured data live in show-tree.nu. This module owns only the
# interactive presentation policy: representable Show-Tree values render as a
# truthful R3CLI tree rebuilt from the rows that actually remain.

const R3CLI_MODULE = (path self ../../vendor/R3CLI/nushell/r3cli)
use $R3CLI_MODULE


def format-tree-size [value: any]: nothing -> string {
    let bytes = ($value | into int)

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


def as-row-list [value: any]: nothing -> list<any> {
    let value_type = ($value | describe)

    if $value_type =~ '^record' {
        return [$value]
    }

    if $value_type =~ '^(list|table)' {
        return ($value | each {|row| $row })
    }

    []
}


def lineage-row [path: string, lineage: list<any>] {
    let matches = ($lineage | where {|row| $row.path == $path })
    if ($matches | is-empty) { null } else { $matches | first }
}


def nearest-visible-parent [
    path: string
    visible_paths: list<any>
    lineage: list<any>
] {
    let source = (lineage-row $path $lineage)
    if $source == null {
        return null
    }

    mut parent = ($source | get --optional parent_path | default null)

    while $parent != null {
        if $parent in $visible_paths {
            return $parent
        }

        let ancestor = (lineage-row $parent $lineage)
        if $ancestor == null {
            return null
        }

        $parent = ($ancestor | get --optional parent_path | default null)
    }

    null
}


def tree-prefix [ancestor_last: list<bool>, is_last: bool] {
    let prefix = (
        $ancestor_last
        | each {|ancestor_is_last| if $ancestor_is_last { '    ' } else { '│   ' } }
        | str join ''
    )

    $prefix + (if $is_last { '└── ' } else { '├── ' })
}


def render-row-line [ui: record, row: record, prefix: string, root: bool] {
    let label = if $root { $row.path } else { $row.name }
    let text = $prefix + ($label | into string)
    let size_text = (format-tree-size $row.size)

    if $row.type == 'dir' {
        r3cli line $ui [
            { text: $text, role: 'heading', bold: true }
            { text: ' [Folder] ', role: 'secondary' }
            { text: ('(' + $size_text + ')'), role: 'value' }
        ]
    } else {
        r3cli line $ui [
            { text: $text, role: 'accent' }
            { text: (' (' + $size_text + ')'), role: 'secondary' }
        ]
    }
}


def render-visible-node [
    ui: record
    rows: list<any>
    row: record
    ancestor_last: list<bool>
    is_last: bool
    root: bool
] {
    let prefix = if $root { '' } else { tree-prefix $ancestor_last $is_last }
    render-row-line $ui $row $prefix $root

    let children = (
        $rows
        | where {|candidate| $candidate._show_tree_parent == $row.path }
        | sort-by _show_tree_order
    )

    for item in ($children | enumerate) {
        let child_is_last = ($item.index == (($children | length) - 1))
        let next_ancestors = if $root { [] } else { [...$ancestor_last $is_last] }
        render-visible-node $ui $rows $item.item $next_ancestors $child_is_last false
    }
}


def render-tree-with-ui [value: any, lineage: list<any>, ui: record]: nothing -> nothing {
    let plain_rows = (as-row-list $value)

    r3cli banner $ui 'SHOW-TREE'

    if ($plain_rows | is-empty) {
        r3cli status $ui warning 'No matching paths.'
        return
    }

    let visible_paths = ($plain_rows | get path)
    let rows = (
        $plain_rows
        | enumerate
        | each {|item|
            $item.item
            | merge {
                _show_tree_order: $item.index
                _show_tree_parent: (nearest-visible-parent $item.item.path $visible_paths $lineage)
            }
        }
    )

    let roots = (
        $rows
        | where {|row| $row._show_tree_parent == null }
        | sort-by _show_tree_order
    )

    for item in ($roots | enumerate) {
        if $item.index > 0 {
            r3cli line $ui
        }
        render-visible-node $ui $rows $item.item [] true true
    }

    let total = ($roots | reduce --fold 0 {|row, acc| $acc + ($row.size | into int) })
    r3cli line $ui
    r3cli key-value $ui 'Total size' (format-tree-size $total)
}


export def show-tree-render-internal [
    value: any
    lineage: list<any>
    hidden_filtered: bool
]: nothing -> nothing {
    let ui = (r3cli console --colour auto)
    render-tree-with-ui $value $lineage $ui

    if $hidden_filtered {
        r3cli status $ui warning 'Hidden entries are omitted. Use --all (-a) to include them.'
    }
}


export def show-tree-render-text-internal [value: any, lineage: list<any>]: nothing -> string {
    let capture_path = ($nu.temp-dir | path join $'show-tree-render-((random uuid)).txt')
    '' | %save --force --raw $capture_path

    let rendered = try {
        let sink = {|text, stream|
            (($text | ansi strip) + (char nl)) | %save --append --raw $capture_path
        }
        let ui = (r3cli console --colour never --sink $sink)
        render-tree-with-ui $value $lineage $ui
        open --raw $capture_path
    } catch {|err|
        if ($capture_path | path exists) {
            rm --force $capture_path
        }
        error make { msg: $'Could not render Show-Tree for saving: ($err.msg)' }
    }

    if ($capture_path | path exists) {
        rm --force $capture_path
    }

    $rendered
}


export def show-tree-can-render-internal [meta: record, value: any]: nothing -> bool {
    if ((($meta | get --optional show_tree_result) | default false) != true) {
        return false
    }

    let lineage = ($meta | get --optional show_tree_render)
    if $lineage == null {
        return false
    }

    let value_type = ($value | describe)
    if $value_type !~ '^(record|list|table)' {
        return false
    }

    let rows = (as-row-list $value)
    if ($rows | is-empty) {
        return true
    }

    let columns = ($rows | columns)
    let required = [name type size path]
    if not ($required | all {|column| $column in $columns }) {
        return false
    }

    if not ($rows | all {|row| ($row.path | describe) == 'string' }) {
        return false
    }
    if not ($rows | all {|row| $row.type in [dir file] }) {
        return false
    }
    if not ($rows | all {|row| ($row.size | describe) =~ '^(filesize|int|float)' }) {
        return false
    }

    let paths = ($rows | get path)
    if (($paths | uniq | length) != ($paths | length)) {
        return false
    }

    let known_paths = ($lineage | get path)
    $paths | all {|path| $path in $known_paths }
}


export-env {
    let already_installed = ($env.SHOW_TREE_DISPLAY_HOOK_INSTALLED? | default false)

    if not $already_installed {
        let previous_display_output = ($env.config.hooks.display_output? | default null)
        let previous_display_type = ($previous_display_output | describe)

        if $previous_display_type == 'string' {
            let wrapped_display_source = (
                "metadata access {|meta| if (show-tree-display show-tree-can-render-internal $meta $in) { show-tree-display show-tree-render-internal $in ($meta | get show_tree_render) (($meta | get --optional show_tree_hidden_filtered) | default false) } else { $in | do { "
                + $previous_display_output
                + " } } }"
            )
            $env.config.hooks.display_output = $wrapped_display_source
        } else {
            $env.config.hooks.display_output = {
                metadata access {|meta|
                    if (show-tree-can-render-internal $meta $in) {
                        show-tree-render-internal $in ($meta | get show_tree_render) (($meta | get --optional show_tree_hidden_filtered) | default false)
                    } else if $previous_display_output == null {
                        $in | table
                    } else {
                        $in | do $previous_display_output
                    }
                }
            }
        }

        $env.SHOW_TREE_DISPLAY_HOOK_INSTALLED = true
    }
}
