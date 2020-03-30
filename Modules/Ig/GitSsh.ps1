<#
.SYNOPSIS
Create the host alias used by Write-SshConfig and Convert-SshAddress.
#>
function Get-SshAlias {
  param (
    [Parameter(Mandatory)] [Hashtable] $HostEntry
  )
  "$($HostEntry.owner)$($HostEntry.host)"
}

<#
.SYNOPSIS
Write hosts section(s) of an SSH config file for use with git.
Pass array of hastables containing owner/host/key entries.
.DESCRIPTION
For instance BitBucket doesn't allow the same SSH key to be used for access
to different users (or teams), so if a CI server has to be setup which clones
with ssh access from repositories from different users multiple keys have to
be used, one per username.
To get this working we define different unique host aliases with each their key file,
so hen one of those aliases is used in a git remote (instead of the actual host name),
the correct key file will be used.
Convert-SshAddress is the counterpart as it takes a git remote and converts the
address using the same convention.
To make this convenient Write-SshConfig/Convert-SshAddress/Install-SshConfig
all work together on the same data structure.
#>
function Write-SshConfig {
  [CmdletBinding(SupportsShouldProcess)]
  param(
    [Parameter(Mandatory)] [AllowEmptyCollection()] [Hashtable[]] $Hosts,
    [Parameter()] [String] $SshDir = (Join-Path $env:USERPROFILE '.ssh'),
    [Parameter()] [String] $LogLevel = 'INFO',
    [Parameter()] [Switch] $Overwrite = $False
  )
  $sshConfigFile = Join-Path $SshDir 'config'
  $fileContent = ""
  foreach($h in $Hosts) {
    Write-Verbose ("Adding {0} to $sshConfigFile" -f (($h.Keys | %{ "$_ $($h[$_])" }) -join ' | ' ))
    $fileContent += "Host {0}`n" -f (Get-SshAlias $h)
    $fileContent += "  User git`n"
    $fileContent += "  Hostname " + $($h.host) + "`n"
    $fileContent += "  PreferredAuthentications publickey`n"
    $fileContent += "  LogLevel $LogLevel`n"
    $fileContent += "  IdentityFile " + $(Join-Path $SshDir $h.key) + "`n"
  }
  Write-Verbose $fileContent
  if($Overwrite) {
    Set-Content $sshConfigFile $fileContent
  }
  else {
    Add-Content $sshConfigFile $fileContent
  }
}

<#
.SYNOPSIS
Write an RSA private key file.
Spaces can be used as seperator, they are converted to newlines.
Useful for e.g. creating key files from strings acquired as an Appveyor
secure environment variable: https://www.appveyor.com/docs/how-to/private-git-sub-modules/
#>
function Write-PrivateRsaKeyFile {
  [CmdletBinding(SupportsShouldProcess)]
  param(
    [Parameter(Mandatory)] [Alias('Key')] [String] $RsaPrivateKey,
    [Parameter(Mandatory)] [Alias('File')] [String] $KeyFile
  )
  $fileContent = "-----BEGIN RSA PRIVATE KEY-----`n"
  $fileContent += "$RsaPrivateKey".Replace(' ', "`n")
  $fileContent += "`n-----END RSA PRIVATE KEY-----`n"
  Write-Verbose "Creating ssh key file $KeyFile"
  Set-Content $KeyFile $fileContent
}

<#
.SYNOPSIS
Convert address in a git remote to an alias corresponding to the same hash passed to Write-SshConfig.
#>
function Convert-SshAddress {
  param (
    [Parameter(Mandatory)] [Alias('Remote', 'Address')] [String] $SshAddress,
    [Parameter(Mandatory)] [AllowEmptyCollection()] [Hashtable[]] $Hosts
  )
  foreach($h in $Hosts) {
    if(-not $SshAddress.Contains("$($h.host)`:$($h.owner)")) {
      continue
    }
    return $SshAddress.Replace($h.host, (Get-SshAlias $h))
  }
  return $SshAddress
}

<#
.SYNOPSIS
Setup ssh for use with git as described per Write-SshConfig.
Pass the hosts hashtable array and a hashtable containing key files/content
which will be written using Write-PrivateRsaKeyFile
.EXAMPLE
$Hosts = @( @{'owner' = 'user1'; 'host' ='bitbucket.org'; 'key' = 'id_rsa_user1'},
            @{'owner' = 'user2'; 'host' ='bitbucket.org'; 'key' = 'id_rsa_user2'},
            @{'owner' = 'user1'; 'host' ='github.com'; 'key' = 'id_rsa_user1'} )

$Keys = @{'id_rsa_user1' = 'key1';
          'id_rsa_user2' = 'key2' }

Install-SshConfig $Hosts $Keys -Verbose -WhatIf
Install-SshConfig $Hosts $Keys
#>
function Install-SshConfig {
  [CmdletBinding(SupportsShouldProcess)]
  param (
    [Parameter(Mandatory)] [AllowEmptyCollection()] [Hashtable[]] $Hosts,
    [Parameter(Mandatory)] [Hashtable] $Keys,
    [Parameter()] [String] $LogLevel = 'INFO',
    [Parameter()] [String] $SshDir = (Join-Path $env:USERPROFILE '.ssh')
  )

  foreach($key in $Keys.Keys) {
    Write-PrivateRsaKeyFile $Keys[$key] (Join-Path $SshDir $key)
  }

  Write-SshConfig $Hosts $SshDir $LogLevel
}
