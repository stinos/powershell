Import-Module ([IO.Path]::Combine($PSScriptRoot, '..', 'Ig'))

<#
.SYNOPSIS
Wrap file.exe for a single file and return the encoding it outputs.
Output is the 'human readable' form of file.exe, but actually only because
using the mime-type form looses information like presence BOM for UTF-8: running
file.exe with -i outputs 'charset=utf-8' whether there's a BOM or not.
.PARAMETER File
File to get encoding for.
.PARAMETER FileExe
Name or path of file.exe, defaulting to the one in standard Windows git installation.
.OUTPUTS
Encoding string
#>
function Read-Encoding {
  param (
    [Parameter(Mandatory, ValueFromPipeline)] [String[]] $File,
    [Parameter()] [String] $FileExe = 'C:\Program Files\Git\usr\bin\file.exe'
  )
  process {
    foreach ($f in $File) {
      # -E = exit with non-zero if file not found.
      # -F = delimit file to be able to split; recent version have -b which doens't output the filename.
      (& $FileExe -E -F '|' $f).Split('|')[1].Trim()
      Test-LastExitCode -Name 'file.exe'
    }
  }
}

<#
.SYNOPSIS
Try to convert encoding produced by file.exe to an encoding Out-File knows.
Only handles most common text types.
.PARAMETER Encoding
Encoding output of file.exe e.g. from Read-Encoding.
.OUTPUTS
Hashtable with Encoding and Ps, the latter a boolean indicating whether
Encoding is the converted one, else the original one.
#>
function Convert-FileEncodingtoPsEncoding {
  param(
    [Parameter(Mandatory, ValueFromPipeline)] [String[]] $Encoding
  )
  process {
    foreach ($enc in $Encoding) {
      if ($enc -match '(?<!-)ASCII text') {
        return @{'Encoding' = 'ascii'; 'Ps' = $true}
      }
      if ($enc -eq 'empty') {
        return @{'Encoding' = 'ascii'; 'Ps' = $true}
      }
      # At some point in 2021, a new file.exe release dropped the 'Unicode ' part.
      if ($enc -match 'UTF-8 (Unicode )?\(with BOM\) text') {
        return @{'Encoding' = 'utf8BOM'; 'Ps' = $true}
      }
      # Some Python files are 'Python script, Unicode text, UTF-8 text executable'
      if ($enc -match 'UTF-8 (Unicode )?text') {
        return @{'Encoding' = 'utf8'; 'Ps' = $true}
      }
      if ($enc -match 'JSON data') {
        return @{'Encoding' = 'utf8'; 'Ps' = $true}
      }
      @{'Encoding' = $enc; 'Ps' = $true}
    }
  }
}

<#
.SYNOPSIS
Write file with given encoding.
.DESCRIPTION
Use IO.StreamWriter directly to write a string to a file.
Out-File in PS versions before PSCore writes utf8 with a BOM so writing without BOM
nees to be done manually. So this function accepts the same utf8 encoding parameters
as Out-File in PSCore, and treats them correctly.
.PARAMETER FilePath
File to write.
.PARAMETER Data
The string to write.
.PARAMETER Encoding
The encoding to use. Only utf8BOM writes a BOM.
Possible values: "utf8", "utf8BOM", "utf8NoBOM", "ascii".
.PARAMETER Append
Append, else overwrite existing file.
#>
function Out-FileWithEncoding {
  [CmdletBinding(SupportsShouldProcess)]
  param (
    [Parameter(Mandatory)] [String] $FilePath,
    [Parameter()] [String] $Data = '',
    [Parameter()] [String]
    [ValidateSet('utf8', 'utf8BOM', 'utf8NoBOM', 'ascii')]
    $Encoding = 'ascii',
    [Parameter()] [Switch] $Append
  )

  if ($Encoding.StartsWith('utf8')) {
    $enc = [Text.UTF8Encoding]::new($Encoding -eq 'utf8BOM')
  }
  else {
    $enc = [Text.ASCIIEncoding]::new()
  }
  try {
    if (-not $PSCmdlet.ShouldProcess($FilePath, 'Write to file')) {
      return
    }
    $FilePath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($FilePath)
    $fileStream = [IO.StreamWriter]::new($FilePath, $Append, $enc)
    $fileStream.Write($Data)
  }
  finally {
    if ($fileStream) {
      $fileStream.Dispose()
    }
  }
}
