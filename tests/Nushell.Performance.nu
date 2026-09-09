use std/assert

const DISPLAY = (path self ../src/nushell/show-tree-display.nu)
use $DISPLAY [show-tree-render-text-internal show-tree-build-render-plan-internal]

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


def benchmark-render [file_count: int] {
    let fixture = (make-flat-tree $file_count)
    let elapsed = (timeit {
        show-tree-render-text-internal $fixture.rows $fixture.lineage | ignore
    })

    { files: $file_count rows: ($file_count + 1) elapsed: $elapsed }
}


def benchmark-plan [file_count: int] {
    let fixture = (make-flat-tree $file_count)
    let elapsed = (timeit {
        show-tree-build-render-plan-internal $fixture.rows $fixture.lineage | ignore
    })

    { files: $file_count rows: ($file_count + 1) elapsed: $elapsed }
}

# End-to-end text rendering includes R3CLI emission and the temporary capture
# sink, while the plan benchmark isolates relationship reconstruction itself.
let render_small = (benchmark-render 500)
let render_large = (benchmark-render 2000)
let plan_small = (benchmark-plan 2000)
let plan_large = (benchmark-plan 8000)

print $'Renderer benchmark:     ($render_small.rows) rows -> ($render_small.elapsed)'
print $'Renderer benchmark:     ($render_large.rows) rows -> ($render_large.elapsed)'
print $'Render-plan benchmark:  ($plan_small.rows) rows -> ($plan_small.elapsed)'
print $'Render-plan benchmark:  ($plan_large.rows) rows -> ($plan_large.elapsed)'

# 4x input should remain comfortably below the old quadratic ~16x growth. The
# factor-8 ceiling leaves room for shared CI runner noise while still detecting
# a return to full-list scans. Absolute limits are deliberately generous.
assert ($render_small.elapsed < 4sec) '501-row renderer benchmark exceeded 4 seconds.'
assert ($render_large.elapsed < 10sec) '2001-row renderer benchmark exceeded 10 seconds.'
assert ($render_large.elapsed < ($render_small.elapsed * 8)) 'Renderer scaling regressed toward quadratic behavior.'
assert ($plan_large.elapsed < ($plan_small.elapsed * 8)) 'Render-plan scaling regressed toward quadratic behavior.'
assert ($plan_large.elapsed < 10sec) '8001-row render-plan benchmark exceeded 10 seconds.'
