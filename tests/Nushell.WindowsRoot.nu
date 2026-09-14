use std/assert

const SHOW_TREE = (path self ../src/nushell/show-tree.nu)
const SHOW_TREE_FORMAT = (path self ../src/nushell/show-tree-format.nu)
use $SHOW_TREE [main]
use $SHOW_TREE_FORMAT ['to showtree']

if $nu.os-info.name != 'windows' {
    print 'Windows-root regression test skipped outside Windows.'
    exit 0
}

for include_hidden in [false true] {
    let rows = if $include_hidden {
        show-tree C:/ --max-depth 1 --all
    } else {
        show-tree C:/ --max-depth 1
    }

    let paths = ($rows | get path)
    let unique_paths = ($paths | uniq)

    assert equal ($unique_paths | length) ($paths | length) $'Windows root scan produced duplicate paths with --all=($include_hidden).'

    let encoded = ($rows | to showtree)
    assert ($encoded | str contains 'schema_version') $'Windows root rows did not serialize as .showtree with --all=($include_hidden).'
}

print 'Nushell Windows-root path identity tests passed.'
