$env.config.max_last_result_size = 1mb

# Keep the pseudo-terminal test independent from Nushell's decorative default prompt.
$env.PROMPT_COMMAND = {|| 'show-tree-test> ' }
$env.PROMPT_COMMAND_RIGHT = {|| '' }
$env.PROMPT_INDICATOR = {|| '' }
$env.PROMPT_INDICATOR_VI_INSERT = {|| '' }
$env.PROMPT_INDICATOR_VI_NORMAL = {|| '' }
$env.PROMPT_MULTILINE_INDICATOR = {|| '::: ' }

const SHOW_TREE = (path self ../show-tree.nu)
use $SHOW_TREE [main]

let show_tree_previous_display_output = ($env.config.hooks.display_output? | default null)
let show_tree_previous_display_type = ($show_tree_previous_display_output | describe)

if $show_tree_previous_display_type == 'string' {
    let show_tree_wrapped_display_source = (
        'metadata access {|meta| if ((($meta | get --optional show_tree_pre_rendered) | default false) == true) { $in | ignore } else { $in | do { '
        + $show_tree_previous_display_output
        + ' } } }'
    )
    $env.config.hooks.display_output = $show_tree_wrapped_display_source
} else {
    $env.config.hooks.display_output = {
        metadata access {|meta|
            if ((($meta | get --optional show_tree_pre_rendered) | default false) == true) {
                $in | ignore
            } else if $show_tree_previous_display_output == null {
                $in | table
            } else {
                $in | do $show_tree_previous_display_output
            }
        }
    }
}
