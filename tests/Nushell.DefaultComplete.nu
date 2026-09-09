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

assert ('root.txt' in $names) 'Default Show-Tree omitted a root file.'
assert ('.hidden.txt' in $names) 'Default Show-Tree omitted a dot-prefixed file.'
assert ('deep.txt' in $names) 'Default Show-Tree did not recurse deeply enough.'
assert (($rows | where type == file | length) >= 3) 'Default Show-Tree should include file rows without --long.'
assert (($rows | where type == dir | length) >= 4) 'Default Show-Tree should include the recursive directory chain.'

let deep_path = ($deep | path join 'deep.txt' | path expand)
assert equal (($rows | where path == $deep_path | first).type) 'file'

# Historical completeness flags remain accepted but are now compatibility no-ops.
let compat = (show-tree $fixture --long --all)
assert equal ($compat | select name type size children path | to nuon) ($rows | select name type size children path | to nuon)

# Explicit filters must still work after the default becomes complete.
let depth_limited = (show-tree $fixture --max-depth 1)
assert ('deep.txt' not-in ($depth_limited | get name)) '--max-depth stopped limiting traversal.'

rm --recursive --force $fixture
print 'Nushell complete-default tests passed.'
