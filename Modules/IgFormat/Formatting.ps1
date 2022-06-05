Import-Module ([IO.Path]::Combine($PSScriptRoot, '..', 'Ig'))

<#
.SYNOPSIS
Describe a code formatter for use with Format-Code.
#>
class CodeFormatter {
  CodeFormatter([String] $name) {
    $this.Name = $Name
  }

  [String] SelectName() {
    return $this.Name
  }

  [String] ArgName() {
    return "$($this.Name)Args"
  }

  [String] DeselectName() {
    return "No$($this.Name)"
  }

  # The name, used for display and in the dynamic parameters, see New-CodeFormatterParameters
  [String] $Name
  # Whether formatter is enabled by default i.e. state when -Name nor -NoName is used.
  [Bool] $OnByDefault = $True
  # The command to execute, arguments: -Items @(<files to format) -Check <check flag> -Arguments <optional arguments>
  [ScriptBlock] $Command = {}
  # Whether extra arguments can be passed to the command.
  [Switch] $TakesArguments
  # Add/modify arguments passed to Format-Code; ScriptBlock with one parameter: the arguments passed
  # by the user, empty Hashtable if no arguments were passed.
  [ScriptBlock] $ApplyDefaultArguments
  # Default file selection if none passed to Format-Code, see Get-FormatterFiles.
  [string[]] $Paths = @()
  # Don't use builtin file listing, but this ScriptBlock instead. Must produce full paths.
  [ScriptBlock] $ListFiles = $null
  # File extensions this formatter is for, see Get-FormatterFiles.
  [string[]] $Extensions = @()
  # Exludeded paths, see Get-FormatterFiles.
  [string[]] $Exclusions = @()
}

<#
.SYNOPSIS
Construct a CodeFormatter instance.
.DESCRIPTION
PS 5 can export classes from modules by 'using <module>' but that has a
number of pitfalls, so instead use this to create instances.
Or, slighlty longer alternative: & (Get-Module Ig) {[CodeFormatter]::new("name")}
.PARAMETER Name
The formatter name.
#>
function New-CodeFormatter {
  param(
    [Parameter()] [String] $Name
  )
  [CodeFormatter]::new($Name)
}

<#
.SYNOPSIS
Retrieve files the given formatter wants to process.
.DESCRIPTION
Gets files for a formatter according to these rules:
- if $Paths is passed, uses those else uses $Formatter.Paths (the latter relative to $FileRoot)
- each of the paths is treated as follows: if a path is an existing file it is used, else it is treated as a
  wildcard pattern: all files are listed with a recursive Get-ChildItem call (or the formatter's ListFiles).
  All resulting items (so also files passed directly) are matched against $Extensions and $Exclusions,
  i.e. only the files not excluded and with a matching extension are returned.
  Note extensions are actual extensions like .ext so not *.ext.

This provides a versatile way of specifying files: none, so everything suitable
gets used (where suitable means: filtered by extension and/or location), or else
a subset or just arbitrary files, while still filtering on extension automatically.

The resulting files are returned as arrays, not flattened. There are 2 reasons:
most external commands will work on a bunch of files in one go so everything must
be collected in an array anyway. But that is also limited by commandline length
(32767 characters) so keeping the batches as-is should alleviate that.
.EXAMPLE
$fmt = [CodeFormatter]::new('Abc')
$fmt.Paths = @('tools', 'api')
$fmt.Extensions = @('.h')
$fmt.Exclusions = @('*\obj\*')

# Get all default files, returning all .h file in tools and api directories,
# though object files in obj/ directories are excluded.
Get-FormatterFiles $fmt

# Get .h files from these directories instead, still excluding obj files.
Get-FormatterFiles $fmt @('foo', 'bar')

# Just use this file
Get-FormatterFiles $fmt 'foo.h'
.PARAMETER Formatter
The formatter.
.PARAMETER Paths
File patterns to scan, if empty use $Formatter.Paths.
.PARAMETER FileRoot
Treat $Formatter.Paths (but not $Paths) as relative to this directory.
Useful to express all default paths for one codebase realative to this root.
.PARAMETER AsHashtable
If true returns hashtables with Path = one of $Paths and Items = corresponding files,
else just returns the files.
.OUTPUTS
One array of full paths for each item in $Paths
#>
function Get-CodeFormatterFiles {
  param(
    [Parameter(Mandatory)] [CodeFormatter] $Formatter,
    [Parameter(ValueFromPipeline)] [String[]] $Paths = @(),
    [Parameter()] [String] $FileRoot = '.',
    [Parameter()] [Switch] $AsHashtable
  )
  $allPaths = $Paths
  if (-not $allPaths) {
    $allPaths = $Formatter.Paths | ForEach-Object {Join-Path $FileRoot $_}
  }
  $Extensions = $Formatter.Extensions | ForEach-Object {"*$_"}
  $result = $allPaths |
    ForEach-Object {
      $items = @()
      if (Test-Path -PathType Leaf -LiteralPath $_) {
        if ((Test-Like $_ $Extensions) -and (Test-NotLike $_ $Formatter.Exclusions)) {
          $items = @($_)
        }
      }
      elseif ($formatter.ListFiles) {
        $items = @(& $formatter.ListFiles $_ | Where-Object {(Test-Like $_ $Extensions) -and (Test-NotLike $_ $Formatter.Exclusions)})
      }
      else {
        $items = @(Get-ChildPaths -File $_ -Exclude $Formatter.Exclusions -Include $Extensions)
      }
      @{'Path' = $_; 'Items' = $items}
    }
  if ($AsHashtable) {
    $result
  }
  else {
    $result | ForEach-Object {, $_.Items}
  }
}

<#
.SYNOPSIS
Create a RuntimeDefinedParameterDictionary with arguments for selecting formatters.
.DESCRIPTION
Use to support dynamic parameters for functions operating on a list of Formatter
instances by creating 3 parameters for each formatter:
- a switch with the formatter name like -Formatter, to enable the formatter
- a switch to do the opposite like -NoFormatter, to disable the formatter; this
  one takes precedence over the previous one.
- optionally, if the formatter takes arguments, an object argument -FormatterArgs,
  to pass arguments to a formatter
See Get-CodeFormatterSelection to parse this again from $PsBoundParameters.
.PARAMETER Formatters
Array of formatters.
.OUTPUTS
The parameter dictionary.
#>
function New-CodeFormatterParameters {
  Param (
    [Parameter(Mandatory)] [CodeFormatter[]] $Formatters,
    [Parameter()] [String] $ParameterSetName
  )
  $fmtSelect = $Formatters | ForEach-Object {$_.SelectName()}
  $fmtDeselect = $Formatters | ForEach-Object {$_.DeselectName()}
  $fmtArgs = $Formatters | Where-Object {$_.TakesArguments} | ForEach-Object {$_.ArgName()}
  $dict = Add-DynamicParameters
  $add = {
    param($Name, $Type)
    Add-DynamicParameters -Names $Name -ParamDictionary $dict -Type $Type -ParameterSetName $ParameterSetName
  }
  & $add $fmtSelect ([Type]'Switch')
  & $add $fmtDeselect ([Type]'Switch')
  & $add $fmtArgs ([Type]'Object')
  $dict
}

<#
.SYNOPSIS
Scan a Hashtable for parameters created by New-CodeFormatterParameters and return selected formatters.
.PARAMETER Formatters
Array of formatters.
.PARAMETER BoundParameters
The $PSBoundParameters variable of the function having the dynamic parameters.
.OUTPUTS
Hashtable with
- Formatters: all of them except default if no arguments passed, or the ones selected with -Formatter,
              and in any case minus the ones deselected by -NoFormatter)
- Arguments: from -FormatterArgs
#>
function Get-CodeFormatterSelection {
  Param (
    [Parameter(Mandatory)] [CodeFormatter[]] $Formatters,
    [Parameter(Mandatory)] [Hashtable] $BoundParameters
  )
  $selected = $Formatters | Where-Object {$BoundParameters.ContainsKey($_.Name)}
  if (-not $selected) {
    $selected = $Formatters | Where-Object {$_.OnByDefault}
  }
  $selected = $selected | Where-Object {-not $BoundParameters.ContainsKey($_.DeselectName())}

  $arguments = @{}
  foreach ($formatter in ($Formatters | Where-Object {$_.TakesArguments})) {
    $argumentName = $formatter.ArgName()
    $arguments[$argumentName] = $BoundParameters[$argumentName]
    if ($null -eq $arguments[$argumentName]) {
      $arguments[$argumentName] = @{}
    }
    if ($formatter.ApplyDefaultArguments) {
      $arguments[$argumentName] = & $formatter.ApplyDefaultArguments $arguments[$argumentName]
    }
  }

  @{
    'Formatters' = $selected;
    'Arguments' = $arguments;
  }
}

<#
.SYNOPSIS
Core function for code formatting and checking thereof.
.DESCRIPTION
Test or run formatting of code. By default formats everything it is configured for.
Use -<Formatter.Name>, -No<Formatter.Name> to select/deselect specific formatters.

Use the -Verbose and -WhatIf flags to get an idea of what happens exactly.

Configuration is done by passing in an array of CodeFormatter instances,
which describe the formatting based on file extension and which files to format
by default. As such this is used to setup code formatting for an entire codebase,
basically by listing its directories and files to format.
.NOTES
This function has all dynamic parameters from New-CodeFormatterParameters,
but they will not show up in argument completion because of how DynamicParam works
(passing -Formatters $MyFormatters results in $Formatters being the string
"$MyFormatters" in the DynamicParam block because it isn't parsed yet).

The previous point plus the fact it's more tedious to constantly have to supply the
Fromatter and FileRoot arguments make it attractive to write a wrapper function though,
and that happens to also be able to solve this dynamic parameter problem: the wrapper
can get dynamic parameters correct by calling New-CodeFormatterParameters with an actual
variable which is in the scope, instead of a parameter. See examples.
.EXAMPLE
# Define dummy formatters used in each example.
$cpp = New-CodeFormatter('Cpp')
$cpp.Command = {param($Items, $Check) Write-Host "clang-format $Items"}
$cpp.Paths = @('lib1', 'speciallib*/subdir')
$cpp.Exclusions = @('*\obj\*', 'speciallibA')
$cpp.Extensions = @('.c', '.cpp', '.h')

$py = New-CodeFormatter('Python')
$py.Command = {param($Items, $Check) Write-Host "black $Items"}
$py.Paths = @('pythonlib1', 'pythonlib2')
$py.Extensions = @('.py')

$Formatters = @($cpp, $py)

# Format everything in Paths specified above.
# This recursively scans 'lib1' and 'speciallib*/subdir' for C++ files, but excludes
# speciallibA and object files. All matches for 'lib1' are passed to $cpp.Command,
# then all matches for 'speciallib*/subdir'.
# A similar process is repeated for Python files in their default directories.
Format-Code -Formatters $Formatters

# Instead of actually formatting, show how much files are found for each formatter.
Format-Code -Formatters $Formatters -WhatIf

# Same effect, but also shows individual files.
Format-Code -Formatters $Formatters -Verbose -WhatIf

# Format everything in Paths specified above, but only Python code.
Format-Code -Formatters $Formatters -Python

# Same effect.
Format-Code -Formatters $Formatters -NoCpp

# Several ways of passing files. Filtering by file type and exclusions still takes place.
Format-Code -Formatters $Formatters -Paths '.'
Format-Code -Formatters $Formatters -Paths @('a', 'b/c')
ls -Directory someothercodebase | %{$_.FullName} | Format-Code -Formatters $Formatters
git -C 'somedir' | %{Join-Path 'somedir' $_} | Format-Code -Formatters $Formatters
.EXAMPLE
# Create a wrapper function which has commandline completion for the dynamic parameters,
# and specifies the formatters to use.
# This is by far the most convenient way to use this.
# Like in example 1, the $Formatters array must be part of the scope the function is in.
function Format-Code {
  [CmdletBinding(SupportsShouldProcess)]
  Param (
    [Parameter(ValueFromPipeline)] [String[]] $Paths,
    [Parameter()] [Switch] $Check,
    # Supply full path to where codebase is.
    [Parameter()] [String] $FileRoot = (Join-Path $PSScriptRoot '..')
  )

  DynamicParam {
    New-CodeFormatterParameters $Formatters
  }

  End {
    # Get values for -Verbose, -WhatIf, -Check, -FileRoot instead of manually writing that. The
    # dynamic parameters will also be here so this can just be splatted, after adding Formatters.
    $params = Get-AllParameters $MyInvocation $PsBoundParameters {Get-Variable @args}
    $params.Formatters = $Formatters
    if ($MyInvocation.ExpectingInput) {
      # To make pipeline work as intended we cannot use the process block because that would
      # leads to calling Ig\Format-Code for every single item pased.
      # Instead use the $Input enumerator, just have to erase Paths.
      $params.Remove('Paths')
      $Input | Ig\Format-Code @params
    }
    else {
      Ig\Format-Code @params
    }
  }
}
.PARAMETER Paths
Use these paths (wildcards/files, see Get-FormatterFiles) instead of the defaults supplied
by each formatter. Takes pipeline input.
.PARAMETER Formatters
Array of CodeFormatter instances.
.PARAMETER Check
Do not actually format files, instead show what would be formatted, and write an error
if anything needs formatting. Use to verify e.g. previous formatting was done correctly.
This might also do additional checks depending on the language.
.PARAMETER Check
Do not actually format files, instead show what would be formatted, and write an error
if anything needs formatting. Use to verify e.g. previous formatting was done correctly.
This might also do additional checks depending on the language.
.PARAMETER Backup
Create a backup of each file, path <file>.bak, before formatting.
.PARAMETER Force
Force overwriting existing backup files. Otherwise formatting is aborted when an existing
backup file is found.
.PARAMETER FileRoot
Search CodeFormatter.Paths relative to this directory.
#>
function Format-Code {
  [CmdletBinding(SupportsShouldProcess)]
  Param (
    [Parameter(ValueFromPipeline)] [String[]] $Paths = @(),
    [Parameter()] [CodeFormatter[]] $Formatters = @(),
    [Parameter()] [Switch] $Check,
    [Parameter()] [Switch] $Backup,
    [Parameter()] [Switch] $Force,
    [Parameter()] [String] $FileRoot = '.'
  )

  DynamicParam {
    if ($Formatters) {
      New-CodeFormatterParameters $Formatters
    }
  }

  Begin {
    $selection = Get-CodeFormatterSelection -Formatters $Formatters -BoundParameters $PSBoundParameters
    $activeFormatters = $selection.Formatters
    foreach ($formatter in $activeFormatters) {
      Write-Verbose "Formatter: $($formatter.Name) $(($selection.Arguments[$formatter.ArgName()] | Out-String).TrimEnd())"
    }
  }

  Process {
    $errors = $null
    foreach ($formatter in $activeFormatters) {
      foreach ($entry in Get-CodeFormatterFiles $formatter -Paths $Paths -FileRoot $FileRoot -AsHashtable) {
        if (-not $PSCmdlet.ShouldProcess("$($entry.Path) ($($entry.Items.Count) items)", "Format $($formatter.Name)")) {
          if ($VerbosePreference) {
            $entry.Items | Write-Verbose
          }
          continue
        }
        if (-not $entry.Items) {
          continue
        }
        Invoke-Command -ErrorVariable '+errors' -ScriptBlock {
          if ($Backup) {
            foreach ($item in $entry.Items) {
              $backupFile = "$item.bak"
              if ((Test-Path $backupFile) -and -not $Force) {
                Write-Error "Backup file exists, won't format: $backupFile"
                return;
              }
              else {
                Copy-Item $item $backupFile -Verbose:$VerbosePreference
              }
            }
          }

          $commandArgs = $selection.Arguments[$formatter.ArgName()]
          & $formatter.Command -Items $entry.Items -Check:$Check -Arguments $commandArgs
        }
      }
    }
  }

  End {
    if ($Check -and $errors) {
      Write-Error 'Code formatting check failed'
    }
    elseif ($errors) {
      Write-Error 'Code formatting failed'
    }
  }
}
