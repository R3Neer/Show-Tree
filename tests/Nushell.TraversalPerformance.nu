use std/assert

const SHOW_TREE = (path self ../src/nushell/show-tree.nu)
use $SHOW_TREE [main]

# This benchmark measures filesystem traversal/normalization rather than the
# renderer. A wide directory is deliberate because it makes Windows hidden-name
# visibility costs easy to measure when evaluating traversal changes. It remains
# in CI even though the attempted visible-name index was rejected as slower.
let fixture = ($nu.temp-dir | path join 'show-tree-traversal-perf')
rm --recursive --force $fixture
mkdir $fixture

let file_count = 1500
0..<$file_count | each {|i|
    '' | save --force ($fixture | path join $'file-($i).txt')
} | ignore

let all_elapsed = (timeit {
    show-tree $fixture --all | ignore
})

let default_elapsed = (timeit {
    show-tree $fixture | ignore
})

print $'Traversal benchmark [($nu.os-info.name)]: --all=($all_elapsed), default=($default_elapsed), files=($file_count)'

assert ($all_elapsed < 30sec) '--all traversal benchmark exceeded 30 seconds.'
assert ($default_elapsed < 30sec) 'default traversal benchmark exceeded 30 seconds.'

rm --recursive --force $fixture
