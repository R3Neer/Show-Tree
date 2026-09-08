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

    print 'Show-Tree installed for Nushell. Open a new Nushell session to load it.'
}
