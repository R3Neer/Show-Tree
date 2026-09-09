use std/assert

const SHOW_TREE = (path self ../show-tree.nu)
const SHOW_TREE_FORMAT = (path self ../show-tree-format.nu)
const SHOW_TREE_SAVE = (path self ../show-tree-save.nu)
use $SHOW_TREE [main]
use $SHOW_TREE_FORMAT ['to showtree' 'from showtree']
use $SHOW_TREE_SAVE save

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

# Normal save still writes the human tree when no .showtree persistence format is
# requested. The filename extension is intentionally irrelevant to this human view.
let saved_tree_path = ($fixture | path join 'saved-tree.txt')
show-tree $fixture --max-depth 2 --long | save --force $saved_tree_path
let saved_tree = (open --raw $saved_tree_path | ansi strip)
assert ($saved_tree | str contains 'SHOW-TREE') 'Saving a Show-Tree result did not write the human tree banner.'
assert ($saved_tree | str contains '├──') 'Saved Show-Tree output is missing tree branch glyphs.'
assert ($saved_tree | str contains 'nested.txt') 'Saved Show-Tree output lost descendant rows.'
assert ($saved_tree | str contains 'Total size') 'Saved Show-Tree output is missing the total-size footer.'
assert (not ($saved_tree | str contains '╭')) 'Saving a Show-Tree result wrote a Nushell table instead of the tree.'

# Row-preserving transforms remain tree-aware when saved as human text.
let filtered_save_path = ($fixture | path join 'filtered-tree.txt')
show-tree $fixture --max-depth 2 --long
| where name in [alpha nested.txt]
| save --force $filtered_save_path
let filtered_saved = (open --raw $filtered_save_path | ansi strip)
assert ($filtered_saved | str contains $alpha_path) 'Filtered save did not promote the retained orphan to a full-path visual root.'
assert ($filtered_saved | str contains 'nested.txt') 'Filtered save lost a retained descendant.'
assert (not ($filtered_saved | str contains 'beta')) 'Filtered save reintroduced a removed node.'

# .showtree is the native persistent snapshot format. Saving by extension stores a
# versioned NUON envelope, while opening by extension restores native rows and the
# private lineage metadata needed for automatic tree rendering.
let snapshot_path = ($fixture | path join 'snapshot.showtree')
$with_files | save --force $snapshot_path
let snapshot_raw = (open --raw $snapshot_path)
assert ($snapshot_raw | str contains 'schema_version') '.showtree did not store a versioned envelope.'
assert ($snapshot_raw | str contains 'producer_version') '.showtree did not store the producer version.'
assert ($snapshot_raw | str contains 'lineage') '.showtree did not persist lineage.'

let reopened_meta = (open $snapshot_path | metadata)
assert equal ($reopened_meta.show_tree_result? | default false) true
assert equal ($reopened_meta.show_tree_render | length) ($with_files | length)
assert equal (($reopened_meta.show_tree_render | where path == $alpha_path | first).parent_path) ($fixture | path expand)
let reopened = (open $snapshot_path)
assert equal ($reopened | columns) $expected_columns
assert equal ($reopened | to nuon) ($with_files | to nuon)

# A filtered snapshot is self-contained. It persists only rows that survived the
# pipeline and records their effective promoted hierarchy, not the hidden original.
let filtered_snapshot_path = ($fixture | path join 'filtered.showtree')
show-tree $fixture --max-depth 2 --long
| where name in [alpha nested.txt]
| save --force $filtered_snapshot_path
let reopened_filtered_meta = (open $filtered_snapshot_path | metadata)
let alpha_lineage = ($reopened_filtered_meta.show_tree_render | where path == $alpha_path | first)
let nested_lineage = ($reopened_filtered_meta.show_tree_render | where path == $nested_path | first)
assert equal $alpha_lineage.parent_path null
assert equal $nested_lineage.parent_path $alpha_path
assert (not (($reopened_filtered_meta.show_tree_render | get path) | any {|path| $path | str contains 'beta' })) 'Filtered .showtree snapshot retained removed lineage.'
let reopened_filtered = (open $filtered_snapshot_path)
assert equal ($reopened_filtered | get name) [alpha nested.txt]
let reopened_filtered_again_meta = (open $filtered_snapshot_path | where name == nested.txt | metadata)
assert equal ($reopened_filtered_again_meta.show_tree_result? | default false) true

# The explicit converter is equivalent to the extension-driven format and can be
# used without a .showtree filename. from showtree restores the same metadata.
let explicit_encoded = ($with_files | to showtree)
let explicit_roundtrip_meta = ($explicit_encoded | from showtree | metadata)
assert equal ($explicit_roundtrip_meta.show_tree_result? | default false) true
let explicit_roundtrip = ($explicit_encoded | from showtree)
assert equal ($explicit_roundtrip | to nuon) ($with_files | to nuon)

let explicit_text_path = ($fixture | path join 'snapshot.data')
$explicit_encoded | save --force $explicit_text_path
assert equal (open --raw $explicit_text_path) $explicit_encoded

# open --raw follows normal Nu semantics and bypasses from showtree.
let raw_opened = (open --raw $snapshot_path)
assert equal ($raw_opened | describe) 'string'
assert ($raw_opened | str contains 'format: show-tree') 'open --raw unexpectedly parsed the .showtree file.'

# Explicit JSON serialization remains explicit: once `to json` consumes the native
# rows, the Show-Tree metadata no longer causes save to render a human tree.
let machine_path = ($fixture | path join 'machine.json')
$with_files | to json | save --force $machine_path
let machine = (open $machine_path)
assert (($machine | describe) =~ '^(list|table)') 'Explicit JSON serialization did not remain machine-readable through the save wrapper.'
assert (($machine | length) == ($with_files | length)) 'Explicit JSON serialization changed the Show-Tree row count.'

# All unrelated values must behave exactly like Nushell's builtin save, including
# automatic extension-based serialization.
let normal_json_path = ($fixture | path join 'normal.json')
[{a: 1} {a: 2}] | save --force $normal_json_path
let normal_json = (open $normal_json_path)
assert equal ($normal_json | get a) [1 2]

# Corrupt and future-schema files must fail clearly instead of returning partial
# data that merely happens to look tree-shaped. `open` may wrap custom parser
# failures, so validate both automatic rejection and the parser's precise message.
let future_path = ($fixture | path join 'future.showtree')
'{format: show-tree, schema_version: 999, producer_version: 9.9.9, rows: [], lineage: []}' | %save --raw --force $future_path
let future_open_error = try {
    open $future_path | ignore
    ''
} catch {|err| $err.msg }
assert (($future_open_error | str trim) != '') 'open accepted an unsupported future .showtree schema.'
let future_parser_error = try {
    open --raw $future_path | from showtree | ignore
    ''
} catch {|err| $err.msg }
assert ($future_parser_error | str contains 'Unsupported .showtree schema version') 'from showtree did not report the unsupported schema version explicitly.'

rm --recursive --force $fixture
print 'Nushell structured-output tests passed.'
