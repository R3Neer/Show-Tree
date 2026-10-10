use std/assert
const SHOW_TREE = (path self ../src/nushell/show-tree.nu)
const FORMAT = (path self ../src/nushell/show-tree-format.nu)
const DISPLAY = (path self ../src/nushell/show-tree-display.nu)
const SAVE = (path self ../src/nushell/show-tree-save.nu)
const CLIP = (path self ../src/nushell/show-tree-clip.nu)
use $SHOW_TREE [main]
use $FORMAT ['to showtree' 'from showtree']
use $DISPLAY
use $DISPLAY [show-tree-render-text-internal]
use $SAVE save
use $CLIP show-tree-clipboard-text-internal

# The PowerShell companion owns the unique fixture and cleans it in finally.
let fixture = $env.SHOW_TREE_DEPTH_FIXTURE
def row [rows: any, name: string] { $rows | where name == $name | first }
for depth in [0 1 2 3] {
    let rows = (show-tree $fixture -d $depth)
    let bytes = [3 25 32 43] | get $depth
    assert equal ($rows | first | get size | into int) $bytes
    assert equal ($rows | first | get size_complete) ($depth == 3)
    assert equal ((row $rows root.txt).size_complete) true
    assert ('.dot' not-in ($rows | get name)) 'Dot directory leaked at boundary.'
    assert ('attribute-hidden' not-in ($rows | get name)) 'Hidden directory leaked at boundary.'
    let boundary_name = [a b c] | get --optional $depth
    if $boundary_name != null {
        let boundary = (row $rows $boundary_name)
        assert equal $boundary.size 0b
        assert equal $boundary.size_complete false
        assert equal $boundary.children []
    }
    let short = (show-tree $fixture -d $depth --short)
    assert equal ($short | first | get size) ($rows | first | get size)
    assert equal ($short | where type == file | length) 0
    let filtered = (show-tree $fixture -d $depth --hide-empty-folders)
    assert equal ($filtered | first | get size_complete) ($depth == 3)
    if $depth == 0 {
        assert ('empty' in ($filtered | get name)) 'Unknown empty folder was hidden.'
    } else {
        assert ('empty' not-in ($filtered | get name)) 'Known empty folder remained.'
    }
    let snapshot = ($rows | to showtree | from showtree)
    assert equal $snapshot $rows 'Snapshot lost completeness.'
    let rendered = (show-tree-render-text-internal $rows (show-tree $fixture -d $depth | metadata | get show_tree_render))
    assert equal ($rendered | str contains '≥') ($depth < 3)
    assert equal (show-tree $fixture -d $depth | show-tree-clipboard-text-internal) $rendered
}

let all_boundary = (show-tree $fixture -d 0 --all)
assert ('.dot' in ($all_boundary | get name)) '--all lost a dot folder at boundary.'
assert ('attribute-hidden' in ($all_boundary | get name)) '--all lost an attribute-hidden folder.'
assert equal ((row $all_boundary '.dot').size_complete) false
assert equal (show-tree $fixture --all | first | get size | into int) 71
assert equal (show-tree $fixture | first | get size_complete) true
assert equal (show-tree ($fixture | path join 'a/b/c') -d 0 | first | get size_complete) true
assert equal (show-tree ($fixture | path join 'hidden-only') -d 0 | first | get size_complete) true
assert equal (show-tree $fixture -d 1 -m 8b | first | get size | into int) 17
assert equal (show-tree $fixture -d 1 -x '*.txt' | first | get size) 0b
assert equal (show-tree $fixture -d 1 -x '*.txt' | first | get size_complete) false
let multi = (show-tree ($fixture | path join 'root.txt') ($fixture | path join 'a') -d 0)
assert equal ($multi | where name == 'root.txt' | first | get size_complete) true
assert equal ($multi | where name == 'a' | first | get size_complete) false

let rows = (show-tree $fixture -d 1 | where name in [a b level1.txt] | sort-by name)
let text = (show-tree-render-text-internal $rows (show-tree $fixture -d 1 | metadata | get show_tree_render))
assert ($text | str contains 'a (≥ 5 B)') 'Transformed rows lost incomplete rendering.'
let saved = ($fixture | path join 'snapshot.showtree')
let human = ($fixture | path join 'tree-output.txt')
show-tree $fixture -d 1 | where name in [a b level1.txt] | sort-by name | save --force $saved
assert equal (open --raw $saved | from showtree) $rows
show-tree $fixture -d 1 | where name in [a b level1.txt] | sort-by name | save --force $human
assert equal (open --raw $human) $text

# Legacy v1 rows do not prove completeness. Preserve their shape, mark directories
# conservatively, and still reject malformed new fields.
let old = ($rows | reject size_complete | to showtree | from showtree)
assert ('size_complete' not-in ($old | columns))
assert ((show-tree-render-text-internal $old ($rows | reject size_complete | to showtree | from showtree | metadata | get show_tree_render)) | str contains '≥')
let malformed = (try { $rows | update size_complete 'wrong' | to showtree | ignore; false } catch { true })
assert $malformed 'Non-boolean completeness was accepted.'
let negative = (try { show-tree $fixture -d -1 | ignore; false } catch { true })
assert $negative 'Negative max depth was accepted.'
let rounding = [{name: 'rounding', type: dir, size: 2047b, size_complete: false, children: [], path: '/rounding'}]
let rounding_text = (show-tree-render-text-internal $rounding [{path: '/rounding', parent_path: null}])
assert ($rounding_text | str contains '(≥ 1.99 KiB)') 'Lower bound rounded upward.'
assert ($rounding_text | str contains 'Total size       ≥ 1.99 KiB') 'Total lower bound rounded upward.'
print 'Nushell depth-boundary tests passed (0/1/2/3/unlimited, filters, snapshots, saves, clipboard, legacy).'
