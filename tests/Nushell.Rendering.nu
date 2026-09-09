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

print 'Nushell folder-glyph rendering test passed.'
