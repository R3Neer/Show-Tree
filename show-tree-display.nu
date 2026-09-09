# Show-Tree display integration for interactive Nushell sessions.
#
# `show-tree.nu` owns traversal and structured data. This module owns only the
# interactive presentation policy: as long as a transformed Show-Tree result still
# contains enough semantic columns to identify its nodes, it is rendered as a
# truthful R3CLI tree built from the rows that actually remain.

const R3CLI_MODULE = (path self vendor/R3CLI/nushell/r3cli)
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


def render-row-line [
    ui: record
    row: record
    prefix: string
    root: bool
] {
    # A promoted orphan becomes a visual root after filtering. Showing its full
    # path keeps that context explicit instead of pretending its omitted ancestors
    # are still present.
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
        let next_ancestors = if $root {
            []
        } else {
            [...$ancestor_last $is_last]
        }

        render-visible-node $ui $rows $item.item $next_ancestors $child_is_last false
    }
}


# Exported because Nushell may store `display_output` as source text. The source
# hook is parsed later by the REPL, so it resolves these helpers through this
# module's stable namespace rather than through lexical imports from config.nu.
export def show-tree-render-internal [value: any, lineage: list<any>]: nothing -> nothing {
    let plain_rows = (as-row-list $value)
    let ui = (r3cli console --colour auto)

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

    let total = (
        $roots
        | reduce --fold 0 {|row, acc| $acc + ($row.size | into int) }
    )

    r3cli line $ui
    r3cli key-value $ui 'Total size' (format-tree-size $total)
}


# A transformed value remains tree-renderable while it still carries Show-Tree
# lineage metadata and keeps the semantic fields needed to identify each row.
# Filters, take/drop, reverse and sort-by therefore stay visual trees. Commands
# such as `get size`, `group-by` or `select name size` naturally fall back to Nu.
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

    let known_paths = ($lineage | get path)
    $rows | all {|row| $row.path in $known_paths }
}


export-env {
    let already_installed = ($env.SHOW_TREE_DISPLAY_HOOK_INSTALLED? | default false)

    if not $already_installed {
        let previous_display_output = ($env.config.hooks.display_output? | default null)
        let previous_display_type = ($previous_display_output | describe)

        if $previous_display_type == 'string' {
            let wrapped_display_source = (
                "metadata access {|meta| if (show-tree-display show-tree-can-render-internal $meta $in) { show-tree-display show-tree-render-internal $in ($meta | get show_tree_render) } else { $in | do { "
                + $previous_display_output
                + " } } }"
            )
            $env.config.hooks.display_output = $wrapped_display_source
        } else {
            $env.config.hooks.display_output = {
                metadata access {|meta|
                    if (show-tree-can-render-internal $meta $in) {
                        show-tree-render-internal $in ($meta | get show_tree_render)
                    } else if $previous_display_output == null {
                        $in | table
                    } else {
                        $in | do $previous_display_output
                    }
                }
            }
        }

        # Prevent accidental double-wrapping when config.nu is sourced more than
        # once in the same session.
        $env.SHOW_TREE_DISPLAY_HOOK_INSTALLED = true
    }
}
