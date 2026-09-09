use std/assert

const DISPLAY = (path self ../src/nushell/show-tree-display.nu)
use $DISPLAY [show-tree-render-text-internal]

# Synthetic flat trees isolate the renderer/indexing cost from filesystem I/O.
# A flat tree is intentionally demanding for the old implementation because
# every leaf used to rescan every visible row to discover that it had no children.
def make-flat-tree [file_count: int] {
    let root = '/show-tree-perf'
    let files = (
        0..<$file_count
        | each {|i|
            {
                name: $'file-($i).txt'
                type: 'file'
                size: 1kb
                children: []
                path: $'($root)/file-($i).txt'
            }
        }
    )

    let rows = ([{
        name: 'show-tree-perf'
        type: 'dir'
        size: (($file_count * 1024) | into filesize)
        children: []
        path: $root
    }] ++ $files)

    let lineage = ([{
        path: $root
        parent_path: null
    }] ++ (
        $files
        | each {|row| { path: $row.path parent_path: $root } }
    ))

    { rows: $rows lineage: $lineage }
}


def benchmark [file_count: int] {
    let fixture = (make-flat-tree $file_count)
    let elapsed = (timeit {
        show-tree-render-text-internal $fixture.rows $fixture.lineage | ignore
    })

    {
        files: $file_count
        rows: ($file_count + 1)
        elapsed: $elapsed
    }
}

# Keep this useful both as a CI regression test and as a maintainer benchmark.
# Thresholds are deliberately generous; the stronger signal is scaling between
# 500 and 2000 leaves rather than runner-to-runner absolute timing.
let small = (benchmark 500)
let large = (benchmark 2000)

print $'Renderer benchmark:  ($small.rows) rows -> ($small.elapsed)'
print $'Renderer benchmark:  ($large.rows) rows -> ($large.elapsed)'

# The optimization work will tighten these assertions once a linear-ish render
# plan is in place. For now they only catch catastrophic hangs in the harness.
assert ($small.elapsed < 30sec) '500-row renderer benchmark exceeded 30 seconds.'
assert ($large.elapsed < 120sec) '2000-row renderer benchmark exceeded 120 seconds.'
