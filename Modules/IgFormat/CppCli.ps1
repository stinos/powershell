<#
.SYNOPSIS
Custom formatting for C++/Cli code, as combination of manual text fixes and clang-format.
#>
. (Join-Path $PSScriptRoot 'Encoding.ps1')

# Some regex constants used.
class Rx{
  static [String] $IdentifierStart = '[_a-zA-Z0-9]'
  static [String] $IdentifierOrTemplate = '[_a-zA-Z0-9][_a-zA-Z0-9]*|>'

  # Types with templates can look like Tuple< String^, String^ >, so for matching against that create
  # a regex where all space is optional (especially since clang-fromat tends to turn '^' into ' ^'),
  # and with '^' escaped to '\^'.
  static [String] EscapeType([string] $value) {
    return $value.Replace(' ', '\s*').Replace('^', '\s*\^')
  }
}

<#
.SYNOPSIS
Parse our formatting instructions, internal use.
.PARAMETER Code
Code to parse for speciial comments.
.OUTPUTS
Hashtable with types and indexers.
#>
function ParseCppCliFormattingInstructions {
  param (
    [Parameter(Mandatory, ValueFromPipeline)] [String] $Code
  )
  #(?m) = multiline so '$' matches end of line
  $types = [Regex]::Matches($Code, '(?m)\/\/\s*cli-type\s+(.+)$') | ForEach-Object {
    $value = $_.Groups[1].Value
    # If it's a template type the MARK has to be added to the type itself so split.
    $templateOpener = $value.IndexOf('<')
    if ($templateOpener -gt -1) {
      @{
        full = $value
        type = $value.Substring(0, $templateOpener)
        template = $value.Substring($templateOpener)
      }
    }
    else {
      @{
        full = $value
        type = $value
        template = ''
      }
    }
  }

  # These can only be plain identifiers so no multiline needed.
  $indexers = [Regex]::Matches($Code, '\/\/\s*cli-indexer\s+(\w+)') | ForEach-Object {
    $_.Groups[1].Value
  }

  @{
    types = $types
    indexers = $indexers
  }
}

<#
.SYNOPSIS
Preprocessing part for PostProcessCppCli.
.DESCRIPTION
clang-format has issues (messed up whitespace and indentation) when encountering C++/CLI 'pointers'
(the ^ and % ones), so the principle used to get proper formatting is:
- scan source file for comments with inctructions for our code, looking like:
    //cli-type SomeType
    //cli-indexer SomeIndexer
- replace denoted
    types with SomeType^ -> SomeTypeMARK*
    indexers with SomeIndexer[type] -> SomeIndexerMARK(type)
  Names are altered to not accidentally replace other types with the same name (e.g. if the code
  already has SomeType* but also SomeType^ then the former must be left as-is).
  Also note that spaces in the parts being replaced are stripped here:
  the actual formatting takes care of that anyway.
- run clang-format which now behaves properly (does mean that line wrapping gets changed somewhat
  but there's just no easy way around).
- run PostProcessCppCli to do reverse replacement again.
.PARAMETER Code
Code to format.
.PARAMETER ForceClangFormatStyle
Apply some formatting which clang-format would also apply itself. Essentially this does the
opposite of the fixes from PostProcessCppCli, so this will mainly add spaces in a couple of locations,
such that when the input code has already been formatted correctly, the output code will
pass the clang-format checks.
Note that the code won't be equal to the final code produced, so when clang-format reports errors
when checking this could be slightly confusing, but there isn't any other way.
.OUTPUTS
Formatted code.
#>
function PreProcessCppCli {
  param (
    [Parameter(Mandatory, ValueFromPipeline)] [String] $Code,
    [Parameter()] [Switch] $ForceClangFormatStyle
  )
  $instructions = ParseCppCliFormattingInstructions $Code

  if ($instructions.types) {
    $instructions.types | ForEach-Object {
      # Match bare type only: can be preceded by space or ( etc, but not another
      # identifer character because that would be another type.
      # Escape the type, since it could in turn contain ^ characters if it's a template.
      $Code = $Code -replace "(?<!$([Rx]::IdentifierStart))$([Rx]::EscapeType($_.full))\s*\^", "$($_.type)MARK$($_.template)*"
    }
  }

  if ($instructions.indexers) {
    $instructions.indexers | ForEach-Object {
      $Code = $Code -replace "(?<!$([Rx]::IdentifierStart))$_\s*\[\s*(\w+)\s*\]", "$_( `$1MARK )"
    }
  }

  if ($ForceClangFormatStyle) {
    # Skip e.g. '[Serializable] public ref class'
    $Code = $Code -replace '(?<!(?:\]|>)\s*)public (ref|enum) (struct|class)', "public`n`n`$1 `$2"
    $Code = $Code -replace '\#using <(\w+)', '#using < $1'
    # Note the '>' to match closing template type.
    $Code = $Code -replace "($([Rx]::IdentifierOrTemplate))(\^|%)", '$1 $2'
    $Code = $Code -replace "($([Rx]::IdentifierOrTemplate))::typeid", '$1 ::typeid'
  }

  $Code
}

<#
.SYNOPSIS
Postprocessing part for PreProcessCppCli, and additional fixes.
.DESCRIPTION
Performs inverse replacements of PreAndPostProcessCli and additionally fixes
these unwanted clang-format artifacts:
- remove newline after 'public' in 'public ref class' and 'public ref struct'
- remove newline after 'public' in 'public enum class'
- remove space in after '<' in '#using < assmbly.dll>'
- remove space after '^' in 'SomeType ^'
- remove space after '%' in 'SomeType %'
- remove space after before '::typeid' in 'bool ::typeid'
.PARAMETER Code
Code to format.
.OUTPUTS
Formatted code.
#>
function PostProcessCppCli {
  param (
    [Parameter(Mandatory, ValueFromPipeline)] [String] $Code
  )
  $instructions = ParseCppCliFormattingInstructions $Code

  if ($instructions.types) {
    $instructions.types | ForEach-Object {
      $Code = $Code -replace "$($_.type)MARK\s*$([Rx]::EscapeType($_.template))\s*\*", "$($_.full)^"
    }
  }

  if ($instructions.indexers) {
    $instructions.indexers | ForEach-Object {
      $Code = $Code -replace "$_\s*\(\s*(\w+)MARK\s*\)", "$_[ `$1 ]"
    }
  }

  $Code = $Code -replace 'public\s+(ref|enum)\s+(struct|class)', 'public $1 $2'
  $Code = $Code -replace '\#using\s+<\s+', '#using <'
  $Code = $Code -replace "($([Rx]::IdentifierOrTemplate))\s+(\^|%)", '$1$2'
  $Code = $Code -replace "($([Rx]::IdentifierOrTemplate))\s+::typeid", '$1::typeid'

  $code
}

<#
.SYNOPSIS
Run PreProcessCppCli on a file.
.PARAMETER FilePath
File with code to format.
.PARAMETER OutputFilePath
Output file, defaults to $FilePath.
.PARAMETER ForceClangFormatStyle
See PreProcessCppCli: use when checking code.
.PARAMETER Encoding
Output encoding. Default = 'ascii'.
#>
function Initialize-ClangFormattedCppCliCode {
  param (
    [Parameter(Mandatory)] [String] $FilePath,
    [Parameter()] [String] $OutputFilePath = $FilePath,
    [Parameter()] [Switch] $ForceClangFormatStyle,
    [Parameter()] [String] $Encoding = 'ascii'
  )
  $code = Get-Content $FilePath -Raw | PreProcessCppCli -ForceClangFormatStyle:$ForceClangFormatStyle
  Out-FileWithEncoding $OutputFilePath -Encoding $Encoding -Data $code
}

<#
.SYNOPSIS
Run PostProcessCppCli on a file, replacing it.
.PARAMETER FilePath
File with code to format.
.PARAMETER Encoding
Output encoding. Default = 'ascii'.
#>
function Update-ClangFormattedCppCliCode {
  param (
    [Parameter(Mandatory)] [String] $FilePath,
    [Parameter()] [String] $Encoding = 'ascii'
  )
  Out-FileWithEncoding $FilePath -Encoding $Encoding -Data (Get-Content $FilePath -Raw | PostProcessCppCli)
}
