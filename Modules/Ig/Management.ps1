# Note this file is named to match the Microsoft.PowerShell.Management module name.
. (Join-Path $PSScriptRoot Operators.ps1)

<#
.SYNOPSIS
Get-ChildItem with filtering on full path.
.DESCRIPTION
Gets everything under $Path, then keeps only what matches $Include and does
not match $Exclude (so that's like Get-ChildItem's parameters with the same name
but functioning on the full path not just the leaf).
.PARAMETER Path
Path(s) to list.
.PARAMETER File
List only files, no directories.
.PARAMETER Exclude
Wildcard(s) to exclude.
.PARAMETER Include
Wildcard(s) to include.
.OUTPUTS
Returns full paths, so no FileInfo or DirectoryInfo objects.
#>
function Get-ChildPaths {
  param(
    [Parameter(Mandatory)] $Path,
    [Switch] $File,
    [Parameter()] $Exclude = @(),
    [Parameter()] $Include = '*'
  )
  Get-ChildItem -Recurse $Path |
    Where-Object {
      if (-not $File -or -not $_.PSIsContainer) {
        ((Test-Like $_.FullName $Include) -and (Test-NotLike $_.FullName $Exclude))
      }
    } |
    ForEach-Object {
      $_.FullName
    }
}

<#
.SYNOPSIS
Split input in chunks.
.DESCRIPTION
Takes input and returns it chunked as complete arrays (i.e. not automatically
unlfattening it which would defeat the purpose).
.PARAMETER Array
Input items.
.PARAMETER ChunkSize
Maximum size of the chunks returned, less if input exhausted.
.OUTPUTS
Individual arrays of size ChunkSize or less.
#>
function Split-Array {
  Param(
    [Parameter(ValueFromPipeline)] [Object[]] $Array,
    [Parameter(Mandatory)] [Int] [ValidateRange(1, [System.Int32]::MaxValue)] $ChunkSize
  )

  Begin {
    $Chunks = [System.Collections.ArrayList]::new()
  }

  Process {
    foreach ($item in $Array) {
      [void] $Chunks.Add($item)
      if ($Chunks.Count -eq $ChunkSize) {
        , @($Chunks)
        [void] $Chunks.Clear()
      }
    }
  }

  End {
    if (($Chunks.Count -gt 0) -or ($null -eq $Array) -or ($Array.Count -eq 0)) {
      , @($Chunks)
    }
  }
}