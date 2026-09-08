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
let expected_columns = [tree name type size depth path]
assert equal ($with_files | columns) $expected_columns
assert (($with_files | length) > 1) 'Structured output should expose one flat row per visible node.'

let root = ($with_files | where depth == 0 | first)
assert equal $root.type 'dir'
assert equal $root.path ($fixture | path expand)
assert (($root.name | str trim) != '') 'Root names must never be blank.'
assert equal $root.tree $root.path
assert (($root.size | into int) > 0) 'Root size should include file bytes.'

let alpha_row = ($with_files | where name == 'alpha' | first)
assert equal $alpha_row.type 'dir'
assert equal $alpha_row.depth 1
assert ($alpha_row.tree | str contains 'alpha') 'Tree presentation column should retain the hierarchy label.'

let nested_row = ($with_files | where name == 'nested.txt' | first)
assert equal $nested_row.type 'file'
assert equal $nested_row.depth 2
assert equal $nested_row.path ($alpha | path join 'nested.txt' | path expand)

let root_file = ($with_files | where name == 'root.txt' | first)
assert equal $root_file.type 'file'
assert equal $root_file.depth 1

let directories_only = (show-tree $fixture --max-depth 2)
assert equal ($directories_only | where type == 'file' | length) 0
assert equal ($directories_only | where name == 'alpha' | length) 1
assert equal ($directories_only | where name == 'alpha' | get 0.depth) 1

let without_empty = (show-tree $fixture --max-depth 2 --hide-empty-folders)
assert equal ($without_empty | where name == 'empty' | length) 0
assert equal ($without_empty | where name == 'alpha' | length) 1

let json = ($with_files | to json)
assert ($json | str contains '"tree"') 'Structured output should serialize its table-friendly rows directly to JSON.'
assert ($json | str contains '"root.txt"') 'JSON should contain visible file rows when --long is used.'
assert (not ($json | str contains '"children"')) 'Default Nushell output should not hide descendants in nested children tables.'

let table_text = ($with_files | table | ansi strip)
assert ($table_text | str contains 'tree') 'Explicit table output should expose the tree column.'
assert ($table_text | str contains 'name') 'Explicit table output should expose semantic names.'
assert ($table_text | str contains 'root.txt') 'Explicit table output should show descendant rows directly.'
assert (not ($table_text | str contains '[table')) 'Explicit table output must not collapse descendants into nested-table placeholders.'

rm --recursive --force $fixture
print 'Nushell structured-output tests passed.'
