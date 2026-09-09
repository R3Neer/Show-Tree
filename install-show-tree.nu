const SCRIPT_DIR = path self .
const POWERSHELL_INSTALLER = ($SCRIPT_DIR | path join 'Install-ShowTree.ps1')


def external-path [name: string] {
    let matches = (which $name | where type == external)
    if ($matches | is-empty) { null } else { $matches | get path | first }
}


# Nushell entry point for installing Show-Tree into Nushell.
# It delegates the filesystem/profile mutation to the shared PowerShell installer
# so there is only one implementation of backup, validation and repair logic.
def main [] {
    # `nu --no-config-file ./install-show-tree.nu` runs in a child Nushell process.
    # Environment variables are inherited from the parent, so this marker lets us
    # detect the common update case where the calling shell already has Show-Tree
    # loaded. That parent process cannot be hot-reloaded by this child installer.
    let parent_had_show_tree = (($env.SHOW_TREE_DISPLAY_HOOK_INSTALLED? | default false) == true)

    let pwsh = (external-path 'pwsh')
    let legacy = if $pwsh == null { external-path 'powershell.exe' } else { null }
    let engine = if $pwsh != null { $pwsh } else { $legacy }

    if $engine == null {
        error make {
            msg: 'Neither PowerShell 7 nor Windows PowerShell is available. Add PowerShell to PATH before running the installer.'
        }
    }

    let forwarded = [
        '-NoLogo'
        '-NoProfile'
        '-ExecutionPolicy'
        'Bypass'
        '-File'
        $POWERSHELL_INSTALLER
        '-NushellOnly'
    ]

    run-external $engine ...$forwarded
    let exit_code = $env.LAST_EXIT_CODE
    if $exit_code != 0 {
        error make { msg: $'Show-Tree Nushell installation failed with exit code ($exit_code).' }
    }

    print 'Show-Tree installed for Nushell.'

    if $parent_had_show_tree {
        print ''
        print 'IMPORTANT: the Nushell session that launched this installer still has the PREVIOUS Show-Tree command loaded.'
        print 'Do not test Show-Tree in that same shell: close it and open a new Nushell session first.'
    } else {
        print 'Open a new Nushell session to load Show-Tree.'
    }
}
