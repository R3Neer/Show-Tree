use std/assert

const SHOW_TREE = (path self ../show-tree.nu)
use $SHOW_TREE [main]

let fixture = ($nu.temp-dir | path join $"show-tree-structured-(random uuid)")
let alpha = ($fixture | path join 'alpha')
let empty = ($fixture | path join 'empty')

mkdir $alpha
mkdir $empty
'abc' | save --force ($fixture | path join 'root.txt')
'hello' | save --force ($alpha | path join 'nested.txt')

let with_files = (show-tree $fixture --max-depth 2 --long)
let expected_columns = [name type size path]
assert equal ($with_files | columns) $expected_columns
assert (($with_files | length) > 1) 'Structured output should expose one flat row per visible node.'

let root = ($with_files | first)
assert equal $root.type 'dir'
assert equal $root.path ($fixture | path expand)
assert (($root.name | str trim) != '') 'Root names must never be blank.'
assert (($root.size | into int) > 0) 'Root size should include file bytes.'

let alpha_row = ($with_files | where name == 'alpha' | first)
assert equal $alpha_row.type 'dir'
assert equal $alpha_row.path ($alpha | path expand)

let nested_row = ($with_files | where name == 'nested.txt' | first)
assert equal $nested_row.type 'file'
assert equal $nested_row.path ($alpha | path join 'nested.txt' | path expand)

let root_file = ($with_files | where name == 'root.txt' | first)
assert equal $root_file.type 'file'

let directories_only = (show-tree $fixture --max-depth 2)
assert equal ($directories_only | where type == 'file' | length) 0
assert equal ($directories_only | where name == 'alpha' | length) 1

let without_empty = (show-tree $fixture --max-depth 2 --hide-empty-folders)
assert equal ($without_empty | where name == 'empty' | length) 0
assert equal ($without_empty | where name == 'alpha' | length) 1

let json = ($with_files | to json)
assert ($json | str contains '"name"') 'Structured output should serialize its public rows directly to JSON.'
assert ($json | str contains '"root.txt"') 'JSON should contain visible file rows when --long is used.'
assert (not ($json | str contains '"children"')) 'Default Nushell output should not hide descendants in nested children tables.'
assert (not ($json | str contains '"depth"')) 'Presentation-only depth must not leak into machine output.'
assert (not ($json | str contains '"tree"')) 'Presentation-only branch labels must not leak into machine output.'

let table_text = ($with_files | table | ansi strip)
for header in [name type size path] {
    assert ($table_text | str contains $header) $"Explicit table output should expose the ($header) column."
}
assert ($table_text | str contains 'root.txt') 'Explicit table output should show descendant rows directly.'
assert (not ($table_text | str contains '[table')) 'Explicit table output must not collapse descendants into nested-table placeholders.'

rm --recursive --force $fixture
print 'Nushell structured-output tests passed.'
