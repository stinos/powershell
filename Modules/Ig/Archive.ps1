<#
.SYNOPSIS
Create zipfile containing relative paths from list of files and the common root.
.DESCRIPTION
Similar to Compress-Archive but supports creating relative paths in the zip file,
making it usable for output from filtering Get-ChildItem etc.
(Using Compress-Archive would place all files in the root of the zip file)
.PARAMETER DestinationPath
Archive path.
.PARAMETER ArchiveRoot
Common root for all paths, relative to which the paths end up in the archive.
.PARAMETER Update
Update an existing file (create if not found).
Else always creates a new file.
.PARAMETER Paths
Paths to archive.
.EXAMPLE
Get-ChildItem "myDir" -Recurse -Force -File $_} |
  Where-Object {$_ -notmatch "somePattern"} |
  Compress-ArchiveEx -DestinationPath $Archive -ArchiveRoot "myDir"
#>
function Compress-ArchiveEx {
  [CmdletBinding(SupportsShouldProcess)]
  param (
    [parameter(Mandatory)] [String] $DestinationPath,
    [parameter(Mandatory)] [String] [ValidateScript({Test-Path -PathType Container $_})] $ArchiveRoot,
    [parameter()] [Switch] $Update,
    [parameter(ValueFromPipeline)] $Paths
  )
  begin {
    if (-not $Update -and (Test-Path $DestinationPath)) {
      Remove-Item $DestinationPath -WhatIf:$WhatIfPreference -Verbose:$VerbosePreference -ErrorAction Stop
    }
    Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem
    if ($Update) {
      $action = "update"
      $openMode = [System.IO.Compression.ZipArchiveMode]::Update
    }
    else {
      $action = "create"
      $openMode = [System.IO.Compression.ZipArchiveMode]::Create
    }
    if ($PSCmdlet.ShouldProcess($DestinationPath, $action)) {
      $DestinationPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($DestinationPath)
      $zipFile = [System.IO.Compression.ZipFile]::Open(($DestinationPath), $openMode)
    }
    $ArchiveRoot = Resolve-Path -LiteralPath $ArchiveRoot
  }

  process {
    foreach ($path in $Paths) {
      $resolvedPath = (Resolve-Path -LiteralPath $path).Path
      # If the $Archive gets created in $ArchiveRoot, it could be discovered while
      # the pipeline is being lazily evaluated.
      if ($resolvedPath -eq $DestinationPath) {
        continue
      }
      $relativePath = $resolvedPath.Replace($ArchiveRoot, "").Trim("\")
      if (-not $PSCmdlet.ShouldProcess($relativePath, "add")) {
        continue
      }
      $zipEntry = $zipFile.CreateEntry($relativePath)
      $zipEntryWriter = New-Object -TypeName System.IO.BinaryWriter $zipEntry.Open()
      $zipEntryWriter.Write([System.IO.File]::ReadAllBytes($resolvedPath))
      $zipEntryWriter.Close()
    }
  }

  end {
    if ($zipFile) {
      $zipFile.Dispose()
    }
  }
}
