
$psBeautifyModulePath = [IO.Path]::Combine((Split-Path -Parent $PSCommandPath), '..', '..', 'Modules', 'PowerShell-Beautifier', 'PowerShell-Beautifier.psd1')

if (-not (Test-Path $psBeautifyModulePath)) {
  Write-Host 'PowerShell-Beautifier not found, initializing submodule'
  $baseDirectory = [IO.Path]::Combine((Split-Path -Parent $PSCommandPath), '..', '..')
  Invoke-Git $baseDirectory submodule update --init --recursive
}

Import-Module $psBeautifyModulePath -Force

# Don't replace super-common aliases.
$psBeautify = Get-Module PowerShell-Beautifier
@('?', '%', 'cd', 'sls', 'cp', 'copy', 'foreach', 'gci') |
%{$psBeautify.PrivateData.ValidCommandNames.Remove($_)}

# Add type accelaretor for lowercase 'object': without it things like very common 'Object'
# remain uppercase whereas other common ones like String are turned into lowercase.
$accel = [powershell].Assembly.GetType("System.Management.Automation.TypeAccelerators")
$accel::Add("object", [System.Object])
$builtinField = $accel.GetField("builtinTypeAccelerators", [System.Reflection.BindingFlags]"Static,NonPublic")
$builtinField.SetValue($builtinField, $accel::Get)

# We don't want spaces after % and ?.
$customSpacing = {
  param($SourceTokens, $TokenIndex)
  if ($SourceTokens[$TokenIndex].Type -eq 'Command' -and (@('?', '%') -eq $SourceTokens[$TokenIndex].Content)) {
    return $false
  }
  $null
}

# Main wrapper function.
function Format-File {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
    [string]$SourcePath,
    [Parameter(Mandatory = $false, ValueFromPipeline = $false)]
    [string]$DestinationPath
  )
  Edit-DTWBeautifyScript -SourcePath $SourcePath -DestinationPath $DestinationPath -NewLine LF -SpaceAfterComma -TreatAllGroupsEqual -AddSpaceAfter $customSpacing
}
