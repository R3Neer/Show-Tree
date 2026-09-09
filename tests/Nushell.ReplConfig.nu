$env.config.max_last_result_size = 1mb

# Keep the pseudo-terminal test independent from Nushell's decorative default prompt.
$env.PROMPT_COMMAND = {|| 'show-tree-test> ' }
$env.PROMPT_COMMAND_RIGHT = {|| '' }
$env.PROMPT_INDICATOR = {|| '' }
$env.PROMPT_INDICATOR_VI_INSERT = {|| '' }
$env.PROMPT_INDICATOR_VI_NORMAL = {|| '' }
$env.PROMPT_MULTILINE_INDICATOR = {|| '::: ' }

const SHOW_TREE = (path self ../show-tree.nu)
const SHOW_TREE_DISPLAY = (path self ../show-tree-display.nu)
use $SHOW_TREE [main]
use $SHOW_TREE_DISPLAY
use $SHOW_TREE_DISPLAY save
