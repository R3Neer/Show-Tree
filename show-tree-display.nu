# Show-Tree display integration for interactive Nushell sessions.
#
# `show-tree.nu` owns traversal and structured data. This module owns only the
# interactive presentation policy: marked Show-Tree rows render as the R3CLI
# tree, while every other value continues through the user's previous display
# hook unchanged.

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


export def show-tree-render []: list<any> -> nothing {
    let rows = $in
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


export-env {
    let already_installed = ($env.SHOW_TREE_DISPLAY_HOOK_INSTALLED? | default false)

    if not $already_installed {
        let previous_display_output = ($env.config.hooks.display_output? | default null)
        let previous_display_type = ($previous_display_output | describe)

        if $previous_display_type == 'string' {
            # Nushell evaluates string display hooks as source. Preserve that
            # source and intercept only a marked list result from Show-Tree.
            let wrapped_display_source = (
                "metadata access {|meta| if ((($meta | get --optional show_tree_result) | default false) == true) and (($in | describe) =~ '^list') { $in | show-tree-render } else { $in | do { "
                + $previous_display_output
                + " } } }"
            )
            $env.config.hooks.display_output = $wrapped_display_source
        } else {
            $env.config.hooks.display_output = {
                metadata access {|meta|
                    let is_show_tree = (
                        ((($meta | get --optional show_tree_result) | default false) == true)
                        and (($in | describe) =~ '^list')
                    )

                    if $is_show_tree {
                        $in | show-tree-render
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
