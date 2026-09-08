# Show-Tree display integration for interactive Nushell sessions.
#
# This module is intentionally separate from show-tree.nu so scripts can import
# the command without changing their global display hook. The installer imports
# this module from config.nu.

export-env {
    let already_installed = ($env.SHOW_TREE_DISPLAY_HOOK_INSTALLED? | default false)

    if not $already_installed {
        let previous_display_output = ($env.config.hooks.display_output? | default null)
        let previous_display_type = ($previous_display_output | describe)

        if $previous_display_type == 'string' {
            # Nushell evaluates string display hooks as source. Keep the previous
            # source intact and wrap it only for values already rendered by
            # Show-Tree. This is how Nushell's default display hook is represented.
            let wrapped_display_source = (
                'metadata access {|meta| if ((($meta | get --optional show_tree_pre_rendered) | default false) == true) { $in | ignore } else { $in | do { '
                + $previous_display_output
                + ' } } }'
            )
            $env.config.hooks.display_output = $wrapped_display_source
        } else {
            $env.config.hooks.display_output = {
                metadata access {|meta|
                    if ((($meta | get --optional show_tree_pre_rendered) | default false) == true) {
                        $in | ignore
                    } else if $previous_display_output == null {
                        $in | table
                    } else {
                        $in | do $previous_display_output
                    }
                }
            }
        }

        # Prevent accidental double-wrapping when config.nu is sourced more than
        # once in the same session.
        $env.SHOW_TREE_DISPLAY_HOOK_INSTALLED = true
    }
}
