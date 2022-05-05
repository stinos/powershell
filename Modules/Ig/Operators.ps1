<#
.SYNOPSIS
Test -notlike with an array of values.
.DESCRIPTION
Performs the equivalent of ($arg -notlike $val1) -and ($arg -notlike $val2) -and ...
i.e. like it would be when -notlike would take an array instead of a single argument.
.PARAMETER What
Value to test.
.PARAMETER NotLike
Values to test -notlike against.
#>
function Test-NotLike {
  param (
    [Parameter(Mandatory)] $What,
    [Parameter()] [Object[]] $NotLike
  )
  if (-not $NotLike) {
    return $What -notlike $null
  }
  # Note: can de done with oneliners like
  # [Linq.Enumerable]::All($NotLike, [func[object, bool]] {param($ex) $What -notlike $ex})
  # but that is about 10 times slower.
  foreach ($li in $NotLike) {
    if (-not ($What -notlike $li)) {
      return $False
    }
  }
  $True
}

<#
.SYNOPSIS
Test -like with an array of values.
.DESCRIPTION
Performs the equivalent of ($arg -like $val1) -or ($arg -like $val2) -or ...
i.e. like it would be when -like would take an array instead of a single argument.
.PARAMETER What
Value to test.
.PARAMETER Like
Values to test -like against.
#>
function Test-Like {
  param (
    [Parameter(Mandatory)] $What,
    [Parameter()] $Like
  )
  if (-not $Like) {
    return $What -like $null
  }
  foreach ($li in $Like) {
    if ($What -like $li) {
      return $True
    }
  }
  $False
}
