<#
.SYNOPSIS
Non-invasive installation by adding to the module path.
#>
function Install-IgModulePath {
  [CmdletBinding()]

  $moduleDir = (Join-Path (Split-Path $PSCommandPath) 'Modules')
  $curPath = [Environment]::GetEnvironmentVariable('PSModulePath')
  if(-not $curPath.Contains($moduleDir)) {
    Write-Verbose "Adding $moduleDir to PSModulePath"
    [Environment]::SetEnvironmentVariable('PSModulePath',"$curPath;$moduleDir")
  }
  else {
    Write-Verbose "PSModulePath already contains $moduleDir"
  }
}

if(-not $args.Contains($False)) {
  Install-IgModulePath -Verbose:$args.Contains('-Verbose')
}
