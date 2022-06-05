. (Join-Path $PSScriptRoot 'CppCli.ps1')
. (Join-Path $PSScriptRoot 'Whitespace.ps1')

<#
.SYNOPSIS
Create CodeFormatter instance for whitespace rules.
.DESCRIPTION
Sets the Name, Command and Extensions properties automatically.
.PARAMETER WhitespaceRules
Collection of WhitespaceRule instances (See WhitespaceRule).
#>
function New-WhitespaceRulesFormatter {
  param($WhitespaceRules)
  $ws = New-CodeFormatter('Whitespace')
  $ws.Extensions = $WhitespaceRules | ForEach-Object { $_.Extensions }
  $ws.Command = {
    param($Items, $Check)
    Format-WhitespaceRules $Items -Test:$Check -WhitespaceRules $WhitespaceRules
  }.GetNewClosure()
  $ws
}

<#
.SYNOPSIS
Create CodeFormatter instance for testing missing whitespace rules.
.DESCRIPTION
Sets the Name, Command and Extensions properties automatically.
.PARAMETER WhitespaceRules
Collection of WhitespaceRule instances (See WhitespaceRule).
#>
function New-WhitespaceRulesTestFormatter {
  param($WhitespaceRules)
  $ws = New-CodeFormatter('TestWhitespace')
  $ws.Extensions = @('.*')
  $ws.Command = {
    param($Items)
    Format-WhitespaceRules $Items -WhitespaceRules $whitespaceRules -ListMissing | Sort-Object -Unique
  }
  $ws
}

<#
.SYNOPSIS
Create CodeFormatter instance for Python code.
.DESCRIPTION
Sets all properties except Paths automatically.
Formats code using Black, checks it using both Black and Flake8.
Arguments to each can be passed: pass a Hashtable like
@{black = @('arg1', 'arg2'); flake8 = @('arg1', 'arg2')}
Default arguments for black are --config pyproject.toml i.e. relative to $pwd,
so meant to be invoked from e.g. all projects root.
#>
function New-PythonFormatter {
  $py = New-CodeFormatter('Python')
  $py.Command = {
    param($Items, $Check, $Arguments)
    $blackArgs = $Arguments['black']
    if (-not $blackArgs) {
      $blackArgs = @('--config', 'pyproject.toml')
    }
    if ($VerbosePreference) {
      $blackArgs += '--verbose'
    }
    if ($Check) {
      $blackArgs += @('--diff', '--check')
    }
    # Need to avoid commandline length limit, so split.
    Split-Array $Items -ChunkSize 128 | ForEach-Object {
      & black @blackArgs $_
      Test-LastExitCode -Name 'black'
    }

    if ($Check) {
      # There doesn't seem to be a way to have it output 'succinct verbose' information
      # i.e. it's like all or nothing so just indicate we're busy.
      Write-Verbose 'Running flake8'
      $flake8Args = $Arguments['flake8']
      Split-Array $Items -ChunkSize 128 | ForEach-Object {
        & flake8 $_ @flake8Args
        Test-LastExitCode -Name 'flake8'
      }
    }
  }
  $py.Extensions = @('.py')
  $py.TakesArguments = $True
  $py
}

<#
.SYNOPSIS
Create CodeFormatter instance for C++ code using clang-format.
.DESCRIPTION
Sets all properties except Paths automatically.
Uses --style=file so looks for .clang-format anywhere up from
the files to be processed.
The command takes a HashTable as argument, with these keys:
- ClangFormat: path to the clang-format executable to use, default = clang-format
- ClangFormatArgs: list with additional arguments to clang-format, default =
    --style=file to look for .clang-format anywhere up from the files to be processed
    --verbose if $VerbosePreference
    --dry-run and --Werror to implement $Check
  Other arguments passed are simply added to this list at the moment, so shouldn't interfere or
  override because that can result in errors.
- CppCliFiles: if a file matches any of the items (using -like) it is treated as C++/CLI code and the fixes
  mentioned in CppCli.ps1 are applied to it. Note using -Check on such C++/CLI files will run on a slightly
  modified copy of the actual source file so some errors can require manual interpretion by the reader
  to figure out what is actually wrong.
#>
function New-CppFormatter {
  $cl = New-CodeFormatter('Cpp')
  $cl.Command = {
    param($Items, $Check, $Arguments)
    $clangFormatArgs = @('--style=file')
    if ($VerbosePreference) {
      $clangFormatArgs += @('--verbose')
    }
    if ($Check) {
      $clangFormatArgs += @('--dry-run', '--Werror')
    }
    else {
      $clangFormatArgs += @('-i')
    }
    if ($Arguments.ContainsKey('ClangFormatArgs')) {
      $clangFormatArgs += $Arguments.ClangFormatArgs
    }
    if ($Arguments.ContainsKey('ClangFormat')) {
      $clangFormat = $Arguments.ClangFormat
    }
    else {
      $clangFormat = 'clang-format'
    }
    if ($Arguments.ContainsKey('CppCliFiles')) {
      $cppCli = $Arguments.CppCliFiles
    }
    else {
      $cppCli = $null
    }
    Split-Array $Items -ChunkSize 128 | ForEach-Object {
      $cliFiles = $_ | Where-Object {Test-Like $_ $cppCli}
      if ($cliFiles -and $Check) {
        $cliFiles = $cliFiles | ForEach-Object {
          # Use filename with prefix: errors should still be recognizable, which wouldn't
          # be the case if we'd use some random temp file name.
          $outputFilePath = Join-Path (Split-Path -Parent $_) "tmp$(Split-Path -Leaf $_)"
          Initialize-ClangFormattedCppCliCode $_ -OutputFilePath $outputFilePath -ForceClangFormatStyle
          $outputFilePath
        }
        try {
          & $clangFormat @clangFormatArgs $cliFiles
        }
        finally {
          $cliFiles | Remove-Item -Force
        }
      }
      else {
        if (-not $Check) {
          $cliFiles | ForEach-Object {Initialize-ClangFormattedCppCliCode $_}
        }
        & $clangFormat @clangFormatArgs $_
        if (-not $Check) {
          $cliFiles | ForEach-Object {Update-ClangFormattedCppCliCode $_}
        }
      }
      Test-LastExitCode -Name 'clang-format'
    }
  }
  $cl.Extensions = @('.h', '.cpp', '.cxx')
  $cl.TakesArguments = $True
  $cl
}
