# Compatibility entrypoint. The implementation lives under src/nushell.
const IMPL = (path self src/nushell/show-tree-display.nu)
export use $IMPL *
