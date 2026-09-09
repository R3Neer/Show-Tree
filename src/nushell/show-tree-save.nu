# Show-Tree-aware wrapper for Nushell's `save`.
#
# Representable Show-Tree values normally save as the same human tree shown in the
# REPL. The .showtree extension is the one exception: without --raw it persists a
# versioned structured snapshot through the native `to showtree` serializer. Every
# unrelated value delegates to Nushell's builtin `%save` unchanged.

const DISPLAY_MODULE = (path self show-tree-display.nu)
const FORMAT_MODULE = (path self show-tree-format.nu)

use $DISPLAY_MODULE [show-tree-can-render-internal show-tree-render-text-internal]
use $FORMAT_MODULE showtree-serialize-internal


def save-builtin [
    value: any
    filename: path
    stderr: any
    raw: bool
    append: bool
    force: bool
    progress: bool
] {
    if $stderr == null {
        $value | %save $filename --raw=$raw --append=$append --force=$force --progress=$progress
    } else {
        $value | %save $filename --stderr=$stderr --raw=$raw --append=$append --force=$force --progress=$progress
    }
}


def filename-extension [filename: path]: nothing -> string {
    let parsed = ($filename | path parse)
    (($parsed | get --optional extension) | default '' | into string | str lowercase)
}


export def save [
    filename: path
    --stderr (-e): path
    --raw (-r)
    --append (-a)
    --force (-f)
    --progress (-p)
] {
    metadata access {|meta|
        let value = $in
        let is_tree = (show-tree-can-render-internal $meta $value)
        let is_showtree_file = ((filename-extension $filename) == 'showtree')

        if $is_showtree_file {
            if $raw {
                save-builtin $value $filename $stderr true $append $force $progress
            } else if $stderr != null {
                save-builtin $value $filename $stderr false $append $force $progress
            } else {
                let serialized = (showtree-serialize-internal $value)
                save-builtin $serialized $filename null true $append $force $progress
            }
            return
        }

        if $is_tree {
            let rendered = (show-tree-render-text-internal $value ($meta | get show_tree_render))
            save-builtin $rendered $filename $stderr $raw $append $force $progress
            return
        }

        save-builtin $value $filename $stderr $raw $append $force $progress
    }
}
