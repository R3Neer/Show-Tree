# Compatibility entrypoint. The implementation lives under src/powershell.
& (Join-Path $PSScriptRoot 'src\powershell\Show-Tree.ps1') @args
