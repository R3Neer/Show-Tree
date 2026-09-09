use std/assert

const SHOW_TREE = (path self ../show-tree.nu)
const SHOW_TREE_FORMAT = (path self ../show-tree-format.nu)
const SHOW_TREE_SAVE = (path self ../show-tree-save.nu)
use $SHOW_TREE [main]
use $SHOW_TREE_FORMAT ['to showtree' 'from showtree']
use $SHOW_TREE_SAVE save

let fixture = ($nu.temp-dir | path join 'showtree-raw-contract')
rm --recursive --force $fixture
mkdir $fixture
'abc' | %save --raw --force ($fixture | path join 'item.txt')

# --raw must keep Nushell's usual meaning even though the filename uses the custom
# extension: the serializer is bypassed and a raw string is written unchanged.
let raw_path = ($fixture | path join 'raw.showtree')
'raw payload' | save --raw --force $raw_path
assert equal (open --raw $raw_path) 'raw payload'
let raw_open_error = try {
    open $raw_path | ignore
    ''
} catch {|err| $err.msg }
assert (($raw_open_error | str trim) != '') 'A raw .showtree payload was unexpectedly parsed as a valid snapshot.'

# `%save` bypasses the Show-Tree wrapper name, but builtin save should still discover
# the globally imported `to showtree` serializer from the .showtree extension.
let value = (show-tree $fixture --max-depth 1 --long)
let builtin_path = ($fixture | path join 'builtin.showtree')
$value | %save --force $builtin_path
let builtin_raw = (open --raw $builtin_path)
assert ($builtin_raw | str contains 'schema_version') 'Builtin %save did not discover to showtree from the extension.'
let builtin_meta = (open $builtin_path | metadata)
assert equal ($builtin_meta.show_tree_result? | default false) true

rm --recursive --force $fixture
print 'Nushell .showtree raw/builtin contract passed.'
