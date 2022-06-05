. (Join-Path $PSScriptRoot Encoding.ps1)

<#
.SYNOPSIS
Count whitespace/tabs/line-endings and get encoding.
.EXAMPLE
Get-ChildItem -File | Measure-WhitespaceAndEncoding | Format-Table
.PARAMETER File
File to test.
.OUTPUTS
Custom object with all information.
#>
function Measure-WhitespaceAndEncoding {
  param (
    [Parameter(Mandatory, ValueFromPipeline)] [String[]] $File
  )
  process {
    foreach ($f in $File) {
      $enc = Read-Encoding $f | Convert-FileEncodingtoPsEncoding
      $data = Get-Content $f -Raw -ErrorAction Stop
      [PSCustomObject] @{
        'File' = $f
        'Lf' = ($data | Select-String -Pattern "(?<!`r)`n" -AllMatches).Matches.Count
        'CrLf' = ($data | Select-String -Pattern "`r`n" -AllMatches).Matches.Count
        'Tabs' = ($data | Select-String -Pattern "`t" -AllMatches).Matches.Count
        'Trail' = ($data | Select-String -Pattern "[ `t]+([`r`n])" -AllMatches).Matches.Count
        'PsEnc' = $enc.Ps
        'Encoding' = $enc.Encoding
      }
    }
  }
}

<#
.SYNOPSIS
Test if a file mathes the given encoding and line-ending, and has no spurious whitespace or tabs.
.PARAMETER File
File to test.
.PARAMETER CrLF
Whether CRLF is expected, else LF.
.PARAMETER NewLineAtEndOfFile
One or zero end of lines.
.PARAMETER Encoding
Expected encoding.
.OUTPUTS
Nothing if everything matches, else informative messages for each problem.
#>
function Test-WhitespaceAndEncoding {
  param (
    [Parameter(Mandatory, ValueFromPipeline)] [String[]] $File,
    [Parameter()] [Switch] $CrLF,
    [Parameter()] [Switch] $NewLineAtEndOfFile,
    [Parameter()] [String] $Encoding = 'utf8'
  )
  process {
    foreach ($f in $File) {
      $data = Get-Content $f -Raw -ErrorAction Stop
      if ($CrLF -and $data -match "(?<!`r)`n") {
        "$f has LF"
      }
      if (-not $CrLF -and $data -match "`r`n") {
        "$f has CRLF"
      }
      if ($data -match "[ `t]+([`r`n])") {
        "$f has trailing whitespace"
      }
      if ($data -match "`t") {
        "$f has tabs"
      }
      if ($data -and $NewLineAtEndOfFile -and -not $data.EndsWith("`n")) {
        "$f has no line end at end of file"
      }
      if (-not $NewLineAtEndOfFile -and $data.EndsWith("`n")) {
        "$f has line end at end of file"
      }
      $fileEncoding = (Read-Encoding $f | Convert-FileEncodingtoPsEncoding).Encoding
      if ($fileEncoding -ne $Encoding) {
        # ASCII is a complete subset of UTF-8.
        if (-not($Encoding -eq 'utf8' -and $fileEncoding -eq 'ascii')) {
          "$f has encoding $fileEncoding"
        }
      }
    }
  }
}

<#
.SYNOPSIS
Rewrite file with new encoding and whitespace treatment.
.DESCRIPTION
Overwrites the file applying the following changes (also the ones
reported by Test-WhitespaceAndEncoding and Measure-WhitespaceAndEncoding):
- replace tabs with 2 spaces
- strip all trailing whitespaces from lines
- use the given line ending
- use the given encoding
See Format-WhitespaceRules to use this for a complete codebase.
.PARAMETER File
File to rewrite.
.PARAMETER CrLF
Whether to write CRLF, else LF.
.PARAMETER NewLineAtEndOfFile
Strip trailing new lines, or make sure there's exactly one.
.PARAMETER Encoding
The encoding to use. See Out-FileWithEncoding.
#>
function Write-WhitespaceAndEncoding {
  param (
    [Parameter(Mandatory, ValueFromPipeline)] [String[]] $File,
    [Parameter()] [Switch] $CrLF,
    [Parameter()] [Switch] $NewLineAtEndOfFile,
    [Parameter()] [String] $Encoding = 'ascii'
  )
  process {
    foreach ($f in $File) {
      $data = Get-Content $f -Raw -ErrorAction Stop
      if (-not $data) {
        $data = ''
      }
      if ($CrLF) {
        $eol = "`r`n"
        $data = $data -replace "(?<!`r)`n", $eol
      }
      else {
        $eol = "`n"
        $data = $data -replace "`r`n", $eol
      }
      $data = $data -replace "[ `t]+([`r`n])", "`$1"
      $data = $data -replace "`t", '  '
      # Note empty files remain as-is here, e.g. pep8 wants this for __init__.py.
      if ($data) {
        $data = $data.TrimEnd()
        if ($NewLineAtEndOfFile) {
          $data += $eol
        }
      }
      Out-FileWithEncoding -FilePath $f -Data $data -Encoding $Encoding
    }
  }
}

<#
.SYNOPSIS
Create Hashtable with whitespace treatment rule for given file extensions.
.DESCRIPTION
An array of these objects gets used to lookup rules by Format-WhitespaceRules.
Defaults to LF line ending and ascii encoding.
.PARAMETER Extensions
File extensions to which the rule applies.
.PARAMETER CrLF
Whether the files should be CRLF, else LF.
.PARAMETER NoNewLineAtEndOfFile
Strip trailing new lines.
.PARAMETER Encoding
Encoding for the files.
.PARAMETER Ignore
Indicates 'no rule' i.e. files with these extensions should not be tested/formatted.
This exists just to make it possible to simply list all possible files in a
project agains and to figure out which extensions have no rule yet.
#>
function New-WhitespaceRule {
  param(
    [Parameter(Mandatory)] [String[]] $Extensions,
    [Parameter()] [Switch] $CrLf,
    [Parameter()] [Switch] $NoNewLineAtEndOfFile,
    [Parameter()] [String] $Encoding = 'ascii',
    [Parameter()] [Switch] $Ignore
  )
  @{
    'Extensions' = $Extensions
    'CrLf' = $CrLf
    'NewLineAtEndOfFile' = -not $NoNewLineAtEndOfFile
    'Encoding' = $Encoding
    'Ignore' = $Ignore
  }
}

<#
.SYNOPSIS
Format or test whitespace rules for a list of files.
.DESCRIPTION
Different file types have different whitespace/line-ending rules,
so to make Write-WhitespaceAndEncoding useful for all code files in a
project the idea is:
- create a 'rule' specifying either to ignore a file, or else telling which
  line-ending and encoding to use (currently we always strip whitespace etc
  so that is not part of the rule)
- map file extensions to whitespace rules
- given a set of files (e.g. output of git ls-files or get-ChildItem),
  match against rules and apply or test rules
.EXAMPLE
$knownFileTypes = @(
  (New-WhitespaceRule @('.ico', '.png', '.tif', '.bmp') -Ignore)
  (New-WhitespaceRule @('.py', '.txt', '.md', '.ps1', '.gitignore') -Encoding 'utf8'),
  (New-WhitespaceRule @('.cs', '.xaml') -CrLf -Encoding 'utf8BOM')
)

git ls-files | Format-WhitespaceRules -Test -WhitespaceRules $knownFileTypes
.PARAMETER Files
Files to rewrite or test
.PARAMETER Test
Test files using Test-WhitespaceAndEncoding writing its output,
and afterwards write an error if any of the files failed. This matches behavior
of other code formatters which can either format or output a diff/error.
.PARAMETER ListMissing
Just list extensions present in Files and for which no matching rule is found.
No files are tested, nor written.
.PARAMETER WhitespaceRules
List of whitespace rules (see New-WhitespaceRules). When a file does not
match any rules or matches an Ignore rule it is skipped. For inspection
the distinction between those is made by running with -Verbose, or
with -ListMissing.
.OUTPUTS
Test-WhitespaceAndEncoding output when $Test is true.
#>
function Format-WhitespaceRules {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory, ValueFromPipeline)] [String[]] $Files,
    [Parameter()] [Switch] $Test,
    [Parameter()] [Switch] $ListMissing,
    [Parameter()] [Hashtable[]] $WhitespaceRules
  )
  begin {
    $failedTest = $False
  }

  process {
    foreach ($File in $Files) {
      $extension = [System.IO.Path]::GetExtension($File)
      # Cannot use Select-Object -First because of https://github.com/PowerShell/PowerShell/issues/9185.
      $matchingRules = @($WhitespaceRules | Where-Object {$_.Extensions -contains $Extension})
      if ($matchingRules) {
        $rule = $matchingRules[0]
      }
      else {
        $rule = $null
      }
      if ($rule -and -not $rule.Ignore -and -not $ListMissing) {
        $ruleArguments = @{
          CrLF = $rule.CrLf
          NewLineAtEndOfFile = $rule.NewLineAtEndOfFile
          Encoding = $rule.Encoding
        }
        if ($Test) {
          $result = Test-WhitespaceAndEncoding $File @ruleArguments
          if ($result) {
            $result
            if ($VerbosePreference) {
              if ($rule.CrLf) {
                $crlf = 'CRLF'
              }
              else {
                $crlf = 'LF'
              }
              "should be $crlf $($rule.Encoding)"
            }
            $failedTest = $true
          }
          elseif ($VerbosePreference) {
            # Not using Write-Verbose here: the idea is that being Verbose for the testing
            # means printing out the result for each file. So for consistency they should
            # be output the same way.
            "$File Ok"
          }
        }
        else {
          Write-WhitespaceAndEncoding $File @ruleArguments
        }
      }
      elseif (-not $rule -and $ListMissing) {
        $extension
      }
      elseif (-not $rule -and $VerbosePreference) {
        Write-Verbose "No whitespace rule found for $File"
      }
    }
  }

  end {
    if ($failedTest) {
      Write-Error 'Found whitespace/encoding mismatches'
    }
  }
}
