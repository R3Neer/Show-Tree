$env.config.max_last_result_size = 1mb

const SHOW_TREE = (path self ../show-tree.nu)
use $SHOW_TREE [main]

let show_tree_previous_display_output = ($env.config.hooks.display_output? | default null)
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
