Set-StrictMode -Version Latest

. (Join-Path $PSScriptRoot 'Encoding.ps1')
. (Join-Path $PSScriptRoot 'Formatting.ps1')
. (Join-Path $PSScriptRoot 'Formatters.ps1')

Export-ModuleMember -Function @(
  'Read-Encoding',
  'Convert-FileEncodingtoPsEncoding',
  'Out-FileWithEncoding'
)

Export-ModuleMember -Function @(
  'New-CodeFormatter',
  'New-CodeFormatterParameters',
  'Format-Code'
)

Export-ModuleMember -Function @(
  'New-WhitespaceRulesFormatter',
  'New-WhitespaceRulesTestFormatter',
  'New-PythonFormatter',
  'New-CppFormatter'
)

Export-ModuleMember -Function @(
  'Measure-WhitespaceAndEncoding',
  'Test-WhitespaceAndEncoding',
  'Write-WhitespaceAndEncoding'
  'New-WhitespaceRule',
  'Format-WhitespaceRules'
)
