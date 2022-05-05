# Pester cannot mock in NestedModules (in the .psd1) nor in Manifest-only modules (i.e. no .psm1),
# so source everything here.
@(
  'Archive.ps1',
  'GitTools.ps1',
  'GitSsh.ps1',
  'Management.ps1',
  'Operators.ps1',
  'Parameters.ps1',
  'Tools.ps1'
) |
  ForEach-Object {
    . (Join-Path $PSScriptRoot $_)
  }
