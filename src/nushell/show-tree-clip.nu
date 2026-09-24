# Clipboard integration for Show-Tree's structured Nushell result.
# A representable tree is copied as the same plain text written by `save`.

const DISPLAY_MODULE = (path self show-tree-display.nu)
use $DISPLAY_MODULE [show-tree-can-render-internal show-tree-render-text-internal]


def clipboard-text [value: any, meta: record]: nothing -> string {
    if (show-tree-can-render-internal $meta $value) {
        show-tree-render-text-internal $value ($meta | get show_tree_render)
    } else {
        $value | to text
    }
}


export def show-tree-clipboard-text-internal [] {
    metadata access {|meta| clipboard-text $in $meta }
}


export def show-tree-clipboard-copy-internal [value: any, meta: record] {
    let text = (clipboard-text $value $meta)

    if $nu.os-info.name == 'windows' {
        $text | ^clip.exe
    } else if ((which pbcopy | where type == external) | is-not-empty) {
        $text | ^pbcopy
    } else if ((which wl-copy | where type == external) | is-not-empty) {
        $text | ^wl-copy
    } else if ((which xclip | where type == external) | is-not-empty) {
        $text | ^xclip -selection clipboard
    } else if ((which xsel | where type == external) | is-not-empty) {
        $text | ^xsel --clipboard --input
    } else {
        error make { msg: 'No supported clipboard command found (clip.exe, pbcopy, wl-copy, xclip or xsel).' }
    }
}
