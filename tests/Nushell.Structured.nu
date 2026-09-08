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
assert equal ($with_files | length) 1
assert equal $with_files.0.type 'dir'
assert equal $with_files.0.path ($fixture | path expand)
assert (($with_files.0.size | into int) > 0) 'Root size should include file bytes.'
assert equal ($with_files.0.children | where name == 'alpha' | length) 1
assert equal ($with_files.0.children | where name == 'empty' | length) 1
assert equal ($with_files.0.children | where name == 'root.txt' | length) 1
assert equal ($with_files.0.children | where name == 'root.txt' | get 0.type) 'file'

let directories_only = (show-tree $fixture --max-depth 2)
assert equal ($directories_only.0.children | where type == 'file' | length) 0
assert equal ($directories_only.0.children | where name == 'alpha' | length) 1
assert equal ($directories_only.0.children | where name == 'alpha' | get 0.children | length) 0

let without_empty = (show-tree $fixture --max-depth 2 --hide-empty-folders)
assert equal ($without_empty.0.children | where name == 'empty' | length) 0
assert equal ($without_empty.0.children | where name == 'alpha' | length) 1

let json = ($with_files | to json)
assert ($json | str contains '"children"') 'Structured output should serialize directly to JSON.'
assert ($json | str contains '"root.txt"') 'JSON should contain visible file nodes when --long is used.'

rm --recursive --force $fixture
print 'Nushell structured-output tests passed.'
