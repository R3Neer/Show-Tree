# Compatibility entrypoint. The implementation lives under src/nushell.
const IMPL = (path self src/nushell/show-tree-format.nu)
export use $IMPL *
