# Compatibility entrypoint. The implementation lives under src/nushell.
const IMPL = (path self src/nushell/show-tree.nu)
export use $IMPL [main show-tree-help tree]
