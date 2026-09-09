# Show-Tree display integration for interactive Nushell sessions.
#
# `show-tree.nu` owns traversal and structured data. This module owns only the
# interactive presentation policy: an unchanged marked Show-Tree value renders as
# the R3CLI tree, while transformed values continue through Nushell's normal
# display path.

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


# Exported because Nushell may store `display_output` as source text. The source
# hook is parsed later by the REPL, so it must resolve these helpers through this
# module's stable namespace rather than through the lexical imports from config.nu.
export def show-tree-render-internal [rows: list<any>]: nothing -> nothing {
    let ui = (r3cli console --colour auto)

    r3cli banner $ui 'SHOW-TREE'

    if ($rows | is-empty) {
        r3cli status $ui warning 'No matching paths.'
        return
    }

    for item in ($rows | enumerate) {
        let row = $item.item
        let is_root = (($row.depth | into int) == 0)

        if $is_root and $item.index > 0 {
            r3cli line $ui
        }

        let size_text = (format-tree-size $row.size)

        if $row.type == 'dir' {
            r3cli line $ui [
                { text: $row.tree, role: 'heading', bold: true }
                { text: ' [Folder] ', role: 'secondary' }
                { text: ('(' + $size_text + ')'), role: 'value' }
            ]
        } else {
            r3cli line $ui [
                { text: $row.tree, role: 'accent' }
                { text: (' (' + $size_text + ')'), role: 'secondary' }
            ]
        }
    }

    let total = (
        $rows
        | where depth == 0
        | get size
        | reduce --fold 0 {|size, acc| $acc + ($size | into int) }
    )

    r3cli line $ui
    r3cli key-value $ui 'Total size' (format-tree-size $total)
}


# Presentation metadata belongs to the exact native value produced by Show-Tree.
# If a user filters, sorts, selects or otherwise changes the rows, fall back to
# Nushell's normal display instead of drawing a stale hierarchy.
export def show-tree-can-render-internal [meta: record, value: any]: nothing -> bool {
    if ((($meta | get --optional show_tree_result) | default false) != true) {
        return false
    }

    let render_rows = ($meta | get --optional show_tree_render)
    let value_type = ($value | describe)
    if $render_rows == null or ($value_type !~ '^(list|table)') {
        return false
    }

    if ($value | is-empty) {
        return ($render_rows | is-empty)
    }

    let columns = ($value | columns)
    if 'path' not-in $columns {
        return false
    }

    ($value | get path) == ($render_rows | get path)
}


export-env {
    let already_installed = ($env.SHOW_TREE_DISPLAY_HOOK_INSTALLED? | default false)

    if not $already_installed {
        let previous_display_output = ($env.config.hooks.display_output? | default null)
        let previous_display_type = ($previous_display_output | describe)

        if $previous_display_type == 'string' {
            # String hooks are parsed only when the REPL later displays a result.
            # Module-qualified helper names survive that deferred parse; bare helper
            # names do not, even though they were visible while config.nu loaded.
            let wrapped_display_source = (
                "metadata access {|meta| if (show-tree-display show-tree-can-render-internal $meta $in) { show-tree-display show-tree-render-internal ($meta | get show_tree_render) } else { $in | do { "
                + $previous_display_output
                + " } } }"
            )
            $env.config.hooks.display_output = $wrapped_display_source
        } else {
            $env.config.hooks.display_output = {
                metadata access {|meta|
                    if (show-tree-can-render-internal $meta $in) {
                        show-tree-render-internal ($meta | get show_tree_render)
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
