<#
.SYNOPSIS
Unzip file.
#>
function Expand-ZipFile {
  param (
    [Parameter(Mandatory)] [Alias('File')] [String] $ZipFile,
    [Parameter(Mandatory)] [Alias('Directory')] [String] $DestinationDirectory
  )

  $shellApplication = New-Object -com shell.application
  $zipPackage = $shellApplication.NameSpace($ZipFile)
  if(-not (Test-Path $DestinationDirectory)) {
    mkdir $DestinationDirectory
  }
  $destinationFolder = $shellApplication.NameSpace($DestinationDirectory)
  Write-Verbose "Extracting $ZipFile to $DestinationDirectory"
  $destinationFolder.CopyHere($zipPackage.Items(), 20)
}

<#
.SYNOPSIS
Download, then unzip.
#>
function Expand-FromWeb {
  param (
    [Parameter(Mandatory)] [Alias('Url')] [String] $Address,
    [Parameter(Mandatory)] [Alias('Directory')] [String] $DestinationDirectory,
    [String] $ZipFile = [IO.Path]::ChangeExtension([IO.Path]::GetTempFileName(), 'zip')
  )

  try {
    Write-Verbose "Downloading $Address to $ZipFile"
    # By default powershell uses TLS 1.0 but the site security might require TLS 1.2
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Invoke-WebRequest $Address -OutFile $ZipFile -ErrorAction Stop
  }
  catch {
    Write-Error $_
    return
  }
  Expand-ZipFile $ZipFile $DestinationDirectory
  Remove-Item $ZipFile
}

<#
.SYNOPSIS
Email sending via implcit SSL.
See http://nicholasarmstrong.com/2009/12/sending-email-with-powershell-implicit-and-explicit-ssl/
#>
function Send-MailMessageOverImplcitSSL {
  param (
    [Parameter(Mandatory)] [String] $To,
    [Parameter(Mandatory)] [String] $From,
    [Parameter()] [String] $Subject = '',
    [Parameter(Mandatory)] [String] $Body,
    [Parameter(Mandatory)] [String] $SmtpServer,
    [Parameter(Mandatory)] [Int] $Port,
    [Parameter(Mandatory)] [String] $Username,
    [Parameter(Mandatory)] [String] $Password
  )

  [System.Reflection.Assembly]::LoadWithPartialName("System.Web") > $null

  $mail = New-Object System.Web.Mail.MailMessage
  $mail.Fields.Add("http://schemas.microsoft.com/cdo/configuration/smtpserver", $SmtpServer)
  $mail.Fields.Add("http://schemas.microsoft.com/cdo/configuration/smtpserverport", $Port)
  $mail.Fields.Add("http://schemas.microsoft.com/cdo/configuration/smtpusessl", $True)
  $mail.Fields.Add("http://schemas.microsoft.com/cdo/configuration/sendusername", $UserName)
  $mail.Fields.Add("http://schemas.microsoft.com/cdo/configuration/sendpassword", $Password)
  $mail.Fields.Add("http://schemas.microsoft.com/cdo/configuration/sendusing", 2)
  $mail.Fields.Add("http://schemas.microsoft.com/cdo/configuration/smtpauthenticate", 1)

  $mail.From = $From
  $mail.To = $To
  $mail.Subject = $Subject
  $mail.Body = $Body

  [System.Web.Mail.SmtpMail]::Send($mail)
}

<#
.SYNOPSIS
Write an error if last external command had an error (check on $LASTEXITCODE).
.PARAMETER CleanupScript
Code to run when an $LASTEXITCODE is non-zero, before raising the error.
.PARAMETER CommandName
Command name to include in error message.
#>
function Test-LastExitCode {
  param (
    [Parameter()] [ScriptBlock] $CleanupScript = $Null,
    [Parameter()] [String] [Alias('Name')] $CommandName = "External command"
  )

  if($LASTEXITCODE -eq 0) {
    return
  }
  if($CleanupScript) {
    & $CleanupScript
  }
  Write-Error "$CommandName exited with $LASTEXITCODE" -Category FromStdErr
}

<#
.SYNOPSIS
Execute external command and throw if it had an error.
Note the default display of the error record will show this function
at the top of the stacktrace i.e. will say "At ...\Tools.ps1:<lineno>"
which is not very useful. Use Test-LastExitCode directly to avoid that.
.PARAMETER ExternalCommand
The command to run, as ScriptBlock.
.PARAMETER CommandName
Command name to include in error message, defaults to $ExternalCommand.
.EXAMPLE
Invoke-External { msbuild my.vcxproj }
#>
function Invoke-External {
  param (
    [Parameter(Mandatory)] [Alias('Command')] [ScriptBlock] $ExternalCommand,
    [Parameter()] [Alias('Name')] [String] $CommandName
  )

  & $ExternalCommand
  if(-not $CommandName) {
    $CommandName = "'$ExternalCommand'"
  }
  Test-LastExitCode -CommandName $CommandName
}

<#
.SYNOPSIS
Pass all lines of the given file to Invoke-External.
#>
function Invoke-File {
  param (
    [Parameter(Mandatory)] [Alias('File')] [ValidateScript({Test-Path $_})] [String] $CommandFile
  )

  foreach($line in (Get-Content $CommandFile)) {
    Invoke-External ([ScriptBlock]::Create($line))
  }
}

<#
.SYNOPSIS
Read environment variables from cmd.exe environment after executing a batch file.
.DESCRIPTION
NOTE this runs 'cmd /D' so disables AutoRun commands from the registry. This should make sure that
the resulting environment is really only the result of the specific batch file (since cmd.exe inherits
the current environment), and doesn't contain other things added via those AutoRun entries
(notably: from Anaconda after having ran conda init in a cmd session).
.PARAMETER BatchFile
The file to call.
.PARAMETER BatchFileArgs
Arguments for the batch file.
.PARAMETER DiffOnly
Scan for items which were added or changed by the batchfile and return only those.
.PARAMETER CompositeKeys
For use with DiffOnly: list of keys which consist of multiple values separated by ';'.
For these the set difference will be returned explcicitly as second argument.
Nore this is just the difference, so if the batch file for instance both adds
items to the front of PATH and appends to it, these items are returned as one list so the
insert/append information is lost.
.OUTPUTS
Hashtable with variables.
If DiffOnly is True and CompositeKeys is not empty, another Hashtable with the changed
items from CompositeKeys as a semicolon-separated string.
#>
function Get-EnvFromBatchFile {
  param (
    [Parameter(Mandatory)] [Alias('File')] [ValidateScript({Test-Path $_})] [String] $BatchFile,
    [Parameter()] [String] $BatchFileArgs = '',
    [Parameter()] [Switch] $DiffOnly,
    [Parameter()] [String[]] $CompositeKeys = @('PATH', 'PsModulePath')
  )

  function Get-EnvVars {
    $vars = @{}
    foreach ($line in (& cmd /D /C @Args)) {
      if ($line -match '(.*?)=(.*)') {
        $vars.Add($Matches[1], $Matches[2])
      }
    }
    $vars
  }

  if ($DiffOnly) {
    $cmdBaseEnvVars = Get-EnvVars 'set'
    if ($CompositeKeys) {
      $compositeVars = @{}
    }
  }

  $vars = @{}
  $cmdEnvVars = Get-EnvVars """$BatchFile"" $BatchFileArgs > nul 2>&1 && set"
  foreach ($item in $cmdEnvVars.GetEnumerator()) {
    $key = $item.key
    $value = $item.value
    if ($DiffOnly -and ($cmdBaseEnvVars[$key] -eq $value)) {
      Write-Verbose "Skip unchanged $key"
      continue
    }
    elseif ($DiffOnly -and ($null -ne $cmdBaseEnvVars[$key]) -and ($key -in $CompositeKeys)) {
      $listSep = ';'  # This is for batch files, so assume we're on Windows.
      $newItems = [Collections.Generic.HashSet[string]]::new($value.Split($listSep))
      $newItems.ExceptWith($cmdBaseEnvVars[$key].Split($listSep))
      $compositeVars[$key] = $newItems -join $listSep
      continue
    }
    $vars[$key] = $value
  }

  $vars
  if ($DiffOnly -and $CompositeKeys) {
    $compositeVars
  }
}

<#
.SYNOPSIS
Read environment variables from cmd.exe environment after executing a batch file,
then apply these variables to the local PowerShell process.
.DESCRIPTION
Use to apply changes from other software wich provides batch files to alter environment variables.
In essence this just consists of executing the batch file then parsing output of 'set' and applying
it by setting variables in env:. There is a bunch of extra code for verbose showing of what goes on,
to aid in debugging.
Note: uses cmd /D, see Get-EnvFromBatchFile.
.PARAMETER BatchFile
The file to call.
.PARAMETER BatchFileArgs
Arguments for the batch file.
.EXAMPLE
Set-EnvFromBatchFile "C:\Program Files (x86)\Microsoft Visual Studio\2019\Community\VC\Auxiliary\Build\vcvars64.bat"
#>
function Set-EnvFromBatchFile {
  [CmdletBinding(SupportsShouldProcess)]
  param (
    [Parameter(Mandatory)] [Alias('File')] [String] $BatchFile,
    [Parameter()] [String] $BatchFileArgs = ''
  )

  Write-Verbose "Set path from $BatchFile"

  $vars = Get-EnvFromBatchFile -BatchFile $BatchFile -BatchFileArgs $BatchFileArgs -DiffOnly -CompositeKeys @()
  foreach ($item in $vars.GetEnumerator()) {
    $key = $item.key
    $value = $item.value
    if ($PSCmdlet.ShouldProcess("Set $key=$value", '?', '')) {
      Set-Item -Force -Path "env:\$key" -Value $value
    }
  }
}

<#
.SYNOPSIS
Read environment variables from cmd.exe environment after executing a batch file,
then write these to a .ps1 file so it can be used to apply the same environment
but without having to execute the actual batch file.
Obviously only interestnig for batch files which don't change.
Inspired by vsdevcmd.bat taking multiple seconds to get the environment for VS ready.
.PARAMETER BatchFile
The file to call.
.PARAMETER PsFile
The PS file to output
.PARAMETER BatchFileArgs
Arguments for the batch file.
#>
function Write-EnvFromBatchFile {
  param (
    [Parameter(Mandatory)] [String] $BatchFile,
    [Parameter(Mandatory)] [String] $PsFile,
    [Parameter()] [String] $BatchFileArgs = '',
    [Parameter()] [Switch] $DiffOnly,
    [Parameter()] [String[]] $CompositeKeys = @('PATH', 'PsModulePath')
  )

  $vars, $compositeVars = Get-EnvFromBatchFile $BatchFile $BatchFileArgs -DiffOnly:$DiffOnly -CompositeKeys $CompositeKeys
  $result = [ArrayList] @()
  foreach ($item in $vars.GetEnumerator()) {
    $result.Add("`$env:$($item.Key) = '$($item.Value)'") | Out-NUll
  }
  if ($compositeVars) {
    foreach ($item in $compositeVars.GetEnumerator()) {
      $result.Add("`$env:$($item.Key) = '$($item.Value)' + ';' + `$env:$($item.Key)") | Out-NUll
    }
  }
  $result | Sort-Object | Out-File -FilePath $PsFile -Encoding ascii
}

<#
.SYNOPSIS
Register a ScriptBlock for being called when files change.
This includes creation, modification, deletion and renaming.
When no ScriptBlock is passed a default one is used which prints information
on each change. Returns the watcher object and all regsitered events.
.EXAMPLE
Register-FileSystemWatcher -Directory c:\temp -Filter '*.c' -IncludeSubdirectories
#>
Function Register-FileSystemWatcher {
  param (
    [Parameter(Mandatory)] [Alias('Folder')] [ValidateScript({Test-Path $_})] [String] $Directory,
    [Parameter()] [Alias('Filter')] [String] $Wildcard = '*.*',
    [Parameter()] [Switch] $IncludeSubdirectories,
    [Parameter()] [Alias('Callback')] [ScriptBlock] $Action
  )

  $watcher = New-Object IO.FileSystemWatcher $Directory, $Wildcard -Property @{
    IncludeSubdirectories = $IncludeSubdirectories
    EnableRaisingEvents = $True
  }

  if(-not $Action -Or ($Null -eq $Action)) {
    $Action = {
      Write-Host "$($Event.TimeGenerated) File $($Event.SourceEventArgs.ChangeType): '$($Event.SourceEventArgs.FullPath)'"
    }
  }

  $changed = Register-ObjectEvent $watcher Changed -Action $Action
  $created = Register-ObjectEvent $watcher Created -Action $Action
  $deleted = Register-ObjectEvent $watcher Deleted -Action $Action
  $renamed = Register-ObjectEvent $watcher Renamed -Action $Action
  return $watcher, $changed, $created, $deleted, $renamed
}

New-Alias -Force -Name Exec -Value Invoke-External
New-Alias -Force -Name Ex -Value Invoke-File
