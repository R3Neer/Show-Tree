# Native .showtree persistence for Nushell.
#
# `to showtree` serializes Show-Tree-compatible native rows as a versioned NUON
# envelope containing the current public rows plus only the effective parent
# relation needed to reconstruct the same forest later. `from showtree` validates
# that envelope and restores the private Show-Tree metadata used by the renderer.

const FORMAT_NAME = 'show-tree'
const SCHEMA_VERSION = 1
const PRODUCER_VERSION = '0.1.3'


def fail [message: string] {
    error make { msg: $message }
}


def as-row-list [value: any]: nothing -> list<any> {
    let value_type = ($value | describe)

    if $value_type =~ '^record' {
        return [$value]
    }

    if $value_type =~ '^(list|table)' {
        return ($value | each {|row| $row })
    }

    []
}


def lineage-row [path: string, lineage: list<any>] {
    let matches = ($lineage | where {|row| $row.path == $path })
    if ($matches | is-empty) { null } else { $matches | first }
}


def validate-rows [rows: list<any>] {
    if ($rows | is-empty) {
        return
    }

    if not ($rows | all {|row| ($row | describe) =~ '^record' }) {
        fail 'Show-Tree rows must be records.'
    }

    if not ($rows | all {|row|
        let columns = ($row | columns)
        [name type size path] | all {|column| $column in $columns }
    }) {
        fail 'Show-Tree rows must contain name, type, size, and path.'
    }

    if not ($rows | all {|row| ($row.name | describe) == 'string' }) {
        fail 'Every Show-Tree row name must be a string.'
    }

    if not ($rows | all {|row| ($row.path | describe) == 'string' }) {
        fail 'Every Show-Tree row path must be a string.'
    }

    if not ($rows | all {|row| $row.type in [dir file] }) {
        fail "Every Show-Tree row type must be 'dir' or 'file'."
    }

    if not ($rows | all {|row| ($row.size | describe) =~ '^(filesize|int|float)' }) {
        fail 'Every Show-Tree row size must be numeric or filesize.'
    }

    if not ($rows | all {|row|
        let children = ($row | get --optional children)
        if $children == null {
            true
        } else {
            (($children | describe) =~ '^(list|table)') and ($children | all {|child| ($child | describe) == 'string' })
        }
    }) {
        fail 'Every Show-Tree children field must be a list of strings when present.'
    }

    let paths = ($rows | get path)
    if (($paths | uniq | length) != ($paths | length)) {
        fail 'Show-Tree row paths must be unique.'
    }
}


def nearest-path-parent [path: string, visible_paths: list<any>] {
    mut current = $path

    loop {
        let parent = ($current | path dirname)
        if ($parent == $current) or ($parent == '') {
            return null
        }
        if $parent in $visible_paths {
            return $parent
        }
        $current = $parent
    }
}


def snapshot-lineage [rows: list<any>]: nothing -> list<record> {
    if ($rows | is-empty) {
        return []
    }

    let visible_paths = ($rows | get path)

    $rows | each {|row|
        {
            path: $row.path
            parent_path: (nearest-path-parent $row.path $visible_paths)
        }
    }
}


def validate-snapshot-lineage [rows: list<any>, lineage: list<any>] {
    if not ($lineage | all {|row| ($row | describe) =~ '^record' }) {
        fail 'Show-Tree lineage entries must be records.'
    }

    if ($rows | is-empty) {
        if not ($lineage | is-empty) {
            fail 'An empty Show-Tree snapshot cannot contain lineage entries.'
        }
        return
    }

    if ($lineage | is-empty) {
        fail 'A non-empty Show-Tree snapshot must contain lineage entries.'
    }

    if not ($lineage | all {|row|
        let columns = ($row | columns)
        ('path' in $columns) and ('parent_path' in $columns)
    }) {
        fail 'Show-Tree lineage must contain path and parent_path.'
    }

    if not ($lineage | all {|row| ($row.path | describe) == 'string' }) {
        fail 'Every Show-Tree lineage path must be a string.'
    }

    if not ($lineage | all {|row|
        let parent = ($row | get --optional parent_path | default null)
        ($parent == null) or (($parent | describe) == 'string')
    }) {
        fail 'Every Show-Tree lineage parent_path must be a string or null.'
    }

    let row_paths = ($rows | get path)
    let lineage_paths = ($lineage | get path)

    if (($lineage_paths | uniq | length) != ($lineage_paths | length)) {
        fail 'Show-Tree lineage paths must be unique.'
    }

    if (($row_paths | sort) != ($lineage_paths | sort)) {
        fail 'Show-Tree rows and lineage must describe exactly the same paths.'
    }

    for entry in $lineage {
        let direct_parent = ($entry | get --optional parent_path | default null)
        if ($direct_parent != null) and ($direct_parent not-in $row_paths) {
            fail $'Show-Tree lineage parent ($direct_parent) is not present in the snapshot.'
        }
        if $direct_parent == $entry.path {
            fail $'Show-Tree lineage path ($entry.path) cannot be its own parent.'
        }

        mut current = $entry.path
        mut seen = []
        loop {
            let current_row = (lineage-row $current $lineage)
            if $current_row == null {
                fail $'Show-Tree lineage path ($current) is missing.'
            }

            let parent = ($current_row | get --optional parent_path | default null)
            if $parent == null {
                break
            }
            if $parent in $seen {
                fail $'Show-Tree lineage contains a parent cycle involving ($parent).'
            }
            $seen = ($seen | append $parent)
            $current = $parent
        }
    }
}


def decode-input [value: any]: nothing -> string {
    let value_type = ($value | describe)

    if $value_type == 'string' {
        return $value
    }
    if $value_type == 'binary' {
        return ($value | decode utf-8)
    }

    fail $'from showtree expects string or binary input, got ($value_type).'
}


export def showtree-serialize-internal [value: any]: nothing -> string {
    let value_type = ($value | describe)
    if $value_type !~ '^(record|list|table)' {
        fail $'to showtree expects Show-Tree-compatible rows, got ($value_type).'
    }

    let rows = (as-row-list $value)
    validate-rows $rows
    let lineage = (snapshot-lineage $rows)

    {
        format: $FORMAT_NAME
        schema_version: $SCHEMA_VERSION
        producer_version: $PRODUCER_VERSION
        rows: $rows
        lineage: $lineage
    } | to nuon
}


export def 'to showtree' []: any -> string {
    showtree-serialize-internal $in
}


export def 'from showtree' []: any -> any {
    let text = (decode-input $in)
    let envelope = try {
        $text | from nuon
    } catch {|err|
        fail $'Invalid .showtree data: ($err.msg)'
    }

    if (($envelope | describe) !~ '^record') {
        fail 'Invalid .showtree data: the top-level value must be a record.'
    }

    if (($envelope | get --optional format) | default '') != $FORMAT_NAME {
        fail $"Invalid .showtree data: format must be '($FORMAT_NAME)'."
    }

    let schema = ($envelope | get --optional schema_version)
    if $schema == null {
        fail 'Invalid .showtree data: schema_version is missing.'
    }
    if (($schema | describe) !~ '^int') {
        fail 'Invalid .showtree data: schema_version must be an integer.'
    }
    if $schema != $SCHEMA_VERSION {
        fail $'Unsupported .showtree schema version ($schema); this Show-Tree supports schema version ($SCHEMA_VERSION).'
    }

    let producer = ($envelope | get --optional producer_version)
    if ($producer == null) or (($producer | describe) != 'string') {
        fail 'Invalid .showtree data: producer_version must be a string.'
    }

    let raw_rows = ($envelope | get --optional rows)
    if $raw_rows == null {
        fail 'Invalid .showtree data: rows are missing.'
    }
    if (($raw_rows | describe) !~ '^(list|table)') {
        fail 'Invalid .showtree data: rows must be a list or table.'
    }
    let rows = (as-row-list $raw_rows)
    validate-rows $rows

    let raw_lineage = ($envelope | get --optional lineage)
    if $raw_lineage == null {
        fail 'Invalid .showtree data: lineage is missing.'
    }
    if (($raw_lineage | describe) !~ '^(list|table)') {
        fail 'Invalid .showtree data: lineage must be a list or table.'
    }
    let lineage = (as-row-list $raw_lineage)
    validate-snapshot-lineage $rows $lineage

    $rows | metadata set {||
        merge {
            show_tree_result: true
            show_tree_render: $lineage
        }
    }
}
