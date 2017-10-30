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
Raise an error if last external command had an error (check on $LastExitCode).
#>
function Test-LastExitCode {
  param (
    [Parameter()] [ScriptBlock] $CleanupScript = $Null
  )

  if($LastExitCode -eq 0) {
    return
  }
  if($CleanupScript) {
    & $CleanupScript
  }
  Write-Error "External command returned exit code $LastExitCode"
}

<#
.SYNOPSIS
Execute external command and throw if it had an error.
.EXAMPLE
Invoke-External { msbuild my.vcxproj }
#>
function Invoke-External {
  param (
    [Parameter(Mandatory)] [Alias('Command')] [ScriptBlock] $ExternalCommand
  )

  & $ExternalCommand
  Test-LastExitCode
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
Read environment variables from batch file and apply them to local PowerShell process.
Note this applies the complete environment as found in a command process after running the batch file.
#>
function Set-EnvFromBatchFile {
  param (
    [Parameter(Mandatory)] [Alias('File')] [ValidateScript({Test-Path $_})] [String] $BatchFile
  )

  Write-Verbose "Set path from $BatchFile"
  cmd /c """$BatchFile""&set" | foreach {
    if ($_ -match "(.*?)=(.*)") {
      Set-Item -force -path "ENV:\$($matches[1])" -value "$($matches[2])"
    }
  }
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

  if(-not $Action -Or ($Action -eq $Null)) {
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
