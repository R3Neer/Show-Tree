use std/assert

const DISPLAY = (path self ../src/nushell/show-tree-display.nu)
use $DISPLAY [show-tree-render-text-internal]

let root = '/show-tree-glyph'
let child = $'($root)/src'
let file = $'($child)/main.nu'

let rows = [
    { name: 'show-tree-glyph', type: 'dir', size: 2kb, children: [src], path: $root }
    { name: 'src', type: 'dir', size: 2kb, children: [main.nu], path: $child }
    { name: 'main.nu', type: 'file', size: 2kb, children: [], path: $file }
]

let lineage = [
    { path: $root, parent_path: null }
    { path: $child, parent_path: $root }
    { path: $file, parent_path: $child }
]

let rendered = (show-tree-render-text-internal $rows $lineage | ansi strip)

assert ($rendered | str contains $'📁 ($root)') 'Root directory is missing the folder glyph.'
assert ($rendered | str contains '└── 📁 src') 'Child directory glyph is not part of the tree prefix.'
assert ($rendered | str contains '└── main.nu') 'File rendering changed unexpectedly.'
assert (not ($rendered | str contains '[Folder]')) 'Legacy [Folder] label is still present.'

# A parent Nushell process stores the installation marker as boolean true, but an
# external child process receives environment variables as strings. Loading the
# display module in that child must treat the inherited string as a stale marker
# and install a fresh process-local hook instead of trying to use it as a bool.
let child_config = ($nu.temp-dir | path join $'show-tree-display-child-((random uuid)).nu')
let display_path = ($DISPLAY | str replace --all '\\' '/')
$"use '($display_path)'" | save --force $child_config

let child_result = (
    with-env { SHOW_TREE_DISPLAY_HOOK_INSTALLED: 'true' } {
        do {
            ^nu --config $child_config -c 'if (($env.SHOW_TREE_DISPLAY_HOOK_INSTALLED? | default false) != true) { error make { msg: "display hook marker was not restored as a process-local bool" } }; print ok'
        } | complete
    }
)

rm --force $child_config

assert equal $child_result.exit_code 0 $'Child process failed to reload display integration: ($child_result.stderr)'

print 'Nushell folder-glyph rendering test passed.'
