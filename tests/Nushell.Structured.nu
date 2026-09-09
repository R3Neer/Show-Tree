use std/assert

const SHOW_TREE = (path self ../show-tree.nu)
use $SHOW_TREE [main]

# Keep this path intentionally short. This test is about the normal table UX,
# not about forcing Nushell's own width-trimming policy with an artificial UUID path.
let fixture = ($nu.temp-dir | path join 'st-ui')
let alpha = ($fixture | path join 'alpha')
let empty = ($fixture | path join 'empty')
let beta = ($fixture | path join 'beta')

rm --recursive --force $fixture
mkdir $alpha
mkdir $empty
mkdir $beta
'abc' | save --force ($fixture | path join 'root.txt')
'hello' | save --force ($alpha | path join 'nested.txt')
'larger child' | save --force ($beta | path join 'beta.txt')

# The interactive display contract depends on custom pipeline metadata reaching
# Nushell's display_output hook. Test that boundary independently of the PTY so a
# rendering failure cannot masquerade as a traversal problem.
let presentation_meta = (show-tree $fixture --max-depth 2 --long | metadata)
assert equal ($presentation_meta.show_tree_result? | default false) true
assert (($presentation_meta.show_tree_render? | default [] | length) > 1) 'Show-Tree render metadata did not survive the command boundary.'
assert equal ($presentation_meta.show_tree_render | get path | first) ($fixture | path expand)
assert ('parent_path' in ($presentation_meta.show_tree_render | columns)) 'Lineage metadata must retain parent paths.'

let with_files = (show-tree $fixture --max-depth 2 --long)
let expected_columns = [name type size children path]
assert equal ($with_files | columns) $expected_columns
assert (($with_files | length) > 1) 'Structured output should expose one flat row per visible node.'

let root = ($with_files | first)
assert equal $root.type 'dir'
assert equal $root.path ($fixture | path expand)
assert (($root.name | str trim) != '') 'Root names must never be blank.'
assert (($root.size | into int) > 0) 'Root size should include file bytes.'
assert equal ($root.children | sort) ([alpha beta empty root.txt] | sort)

let alpha_path = ($alpha | path expand)
let alpha_row = ($with_files | where path == $alpha_path | first)
assert equal $alpha_row.name 'alpha'
assert equal $alpha_row.type 'dir'
assert equal $alpha_row.children [nested.txt]

let nested_path = ($alpha | path join 'nested.txt' | path expand)
let nested_row = ($with_files | where path == $nested_path | first)
assert equal $nested_row.name 'nested.txt'
assert equal $nested_row.type 'file'
assert equal $nested_row.children []

let root_file_path = ($fixture | path join 'root.txt' | path expand)
let root_file = ($with_files | where path == $root_file_path | first)
assert equal $root_file.name 'root.txt'
assert equal $root_file.type 'file'

let directories_only = (show-tree $fixture --max-depth 2)
assert equal ($directories_only | where type == 'file' | length) 0
assert equal ($directories_only | where path == $alpha_path | length) 1
let directories_root = ($directories_only | first)
assert equal ($directories_root.children | sort) ([alpha beta empty] | sort)

let empty_path = ($empty | path expand)
let without_empty = (show-tree $fixture --max-depth 2 --hide-empty-folders)
assert equal ($without_empty | where path == $empty_path | length) 0
assert equal ($without_empty | where path == $alpha_path | length) 1

# Filters, sorting and slicing must keep the Show-Tree metadata that allows the
# interactive hook to reconstruct a tree from the rows that remain.
let filtered_meta = (
    show-tree $fixture --max-depth 2 --long
    | where name in [alpha nested.txt]
    | metadata
)
assert equal ($filtered_meta.show_tree_result? | default false) true

let sorted_meta = (
    show-tree $fixture --max-depth 2 --long
    | sort-by size
    | metadata
)
assert equal ($sorted_meta.show_tree_result? | default false) true

let sliced_meta = (
    show-tree $fixture --max-depth 2 --long
    | take 3
    | metadata
)
assert equal ($sliced_meta.show_tree_result? | default false) true

let json = ($with_files | to json)
assert ($json | str contains '"name"') 'Structured output should serialize semantic basenames directly to JSON.'
assert ($json | str contains '"path"') 'Structured output should serialize full paths directly to JSON.'
assert ($json | str contains '"children"') 'Structured output should expose direct child names.'
assert ($json | str contains 'nested.txt') 'JSON should contain visible file rows when --long is used.'
assert (not ($json | str contains '"parent_path"')) 'Lineage-only parent paths must not leak into machine output.'
assert (not ($json | str contains '"depth"')) 'Presentation-only depth must not leak into machine output.'
assert (not ($json | str contains '"tree"')) 'Presentation-only branch labels must not leak into machine output.'

let table_text = ($with_files | table | ansi strip)
for header in [name type size children path] {
    assert ($table_text | str contains $header) $"Explicit table output should expose the ($header) column for ordinary paths."
}
assert ($table_text | str contains 'root.txt') 'Explicit table output should show descendant rows directly.'
assert ($table_text | str contains 'nested.txt') 'Flat children should remain readable as list values.'
assert (not ($table_text | str contains '[table')) 'Explicit table output must not collapse descendants into nested-table placeholders.'

rm --recursive --force $fixture
print 'Nushell structured-output tests passed.'
