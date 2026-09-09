use std/assert

if $nu.os-info.name != 'windows' {
    print 'Nushell Windows-hidden test skipped on non-Windows platform.'
    exit 0
}

const SHOW_TREE = (path self ../src/nushell/show-tree.nu)
use $SHOW_TREE [main]

let fixture = ($nu.temp-dir | path join 'show-tree-windows-hidden')
let visible = ($fixture | path join 'visible.txt')
let hidden = ($fixture | path join 'attribute-hidden.txt')

rm --recursive --force $fixture
mkdir $fixture
'visible' | save --force $visible
'hidden' | save --force $hidden

let hide_result = (^attrib +H $hidden | complete)
if $hide_result.exit_code != 0 {
    error make { msg: $'Could not mark Windows test file hidden: ($hide_result.stderr)' }
}

let default_rows = (show-tree $fixture)
assert ('visible.txt' in ($default_rows | get name)) 'Default Nushell Show-Tree omitted the visible Windows file.'
assert ('attribute-hidden.txt' not-in ($default_rows | get name)) 'Default Nushell Show-Tree exposed a Windows Hidden-attribute file.'

let all_rows = (show-tree $fixture --all)
assert ('attribute-hidden.txt' in ($all_rows | get name)) '--all did not include a Windows Hidden-attribute file.'

^attrib -H $hidden | ignore
rm --recursive --force $fixture
print 'Nushell Windows Hidden-attribute test passed.'
