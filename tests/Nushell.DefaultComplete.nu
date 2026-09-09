use std/assert

const SHOW_TREE = (path self ../src/nushell/show-tree.nu)
use $SHOW_TREE [main]

let fixture = ($nu.temp-dir | path join 'show-tree-default-complete')
let deep = ($fixture | path join 'a/b/c')

rm --recursive --force $fixture
mkdir $deep

'root' | save --force ($fixture | path join 'root.txt')
'hidden' | save --force ($fixture | path join '.hidden.txt')
'deep' | save --force ($deep | path join 'deep.txt')

let rows = (show-tree $fixture)
let names = ($rows | get name)
let default_meta = (show-tree $fixture | metadata)

assert ('root.txt' in $names) 'Default Show-Tree omitted a visible root file.'
assert ('.hidden.txt' not-in $names) 'Default Show-Tree should omit dot-prefixed entries.'
assert ('deep.txt' in $names) 'Default Show-Tree did not recurse deeply enough.'
assert (($rows | where type == file | length) >= 2) 'Default Show-Tree should include visible file rows.'
assert (($rows | where type == dir | length) >= 4) 'Default Show-Tree should include the recursive directory chain.'
assert equal ($default_meta.show_tree_hidden_filtered? | default false) true

let deep_path = ($deep | path join 'deep.txt' | path expand)
assert equal (($rows | where path == $deep_path | first).type) 'file'

let all_rows = (show-tree $fixture --all)
let all_meta = (show-tree $fixture --all | metadata)
assert ('.hidden.txt' in ($all_rows | get name)) '--all did not include a dot-prefixed file.'
assert equal ($all_meta.show_tree_hidden_filtered? | default true) false

let short_rows = (show-tree $fixture --short)
assert equal ($short_rows | where type == file | length) 0 '--short should suppress file rows.'
assert (($short_rows | where type == dir | length) >= 4) '--short should keep the recursive directory tree.'
assert (($short_rows | first | get size | into int) > 0) '--short directory sizes should still account for visible files.'

# Explicit filters must still work with the new default/short/all policy.
let depth_limited = (show-tree $fixture --max-depth 1)
assert ('deep.txt' not-in ($depth_limited | get name)) '--max-depth stopped limiting traversal.'

rm --recursive --force $fixture
print 'Nushell default/all/short tests passed.'
