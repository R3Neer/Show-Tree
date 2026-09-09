# Compatibility entrypoint. The implementation lives under src/nushell.
const IMPL = (path self src/nushell/show-tree-save.nu)
export use $IMPL save
