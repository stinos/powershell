. (Join-Path (Split-Path $PSCommandPath) Tools.ps1)

<#
.SYNOPSIS
Run git, Powershell-style.
.DESCRIPTION
By default some git commands (clone, checkout, ...) write a part of their
output to stderr, resulting in PS treating that as an error.
Here we work around that by redirecting stderr and using git's exit code
to check if something was actually wrong, and use Write-Error if that's the case,
i.e. standard PS error handling which works with -ErrorAction/-ErrorVariable etc.
The command can be passed as a string or as separate strings.
Additionally takes a $Directory argument which when used has the same effect as git -C,
but also works for clone/stash/submodule/... commands making it easier to automate those.
The $Git argument can be used to specify the executable.
.EXAMPLE
Invoke-Git status
Invoke-Git -Directory some/path status
Invoke-Git 'push -v'
Invoke-Git -Verbose -- push -v  # Pass that last -v to git.
#>
function Invoke-Git {
  [CmdletBinding()]
  param(
    [Parameter()] [Alias('Dir')] [String] $Directory = $null,
    [Parameter()] [String] $Git = 'git',
    [Parameter(Mandatory, Position = 0, ValueFromRemainingArguments = $true)] [string] $Command
  )
  $currentDir = $null
  try {
    $commandParts = $Command.Split(' ')
    $subCommand = $commandParts[0]
    # Not strictly needed for git, but since we rely on subcommand being the first one.
    if ($subCommand.StartsWith('-')) {
      Write-Error "First item in Command argument should be a git command, not a flag: $Command"
      return
    }
    if ($Directory -and $subCommand -eq 'clone') {
      # To make all commands look alike handle this one as well.
      $Command = ($commandParts + @($Directory)) -join ' '
    }
    elseif ($Directory -and @('submodule', 'stash', 'init') -eq $subCommand) {
      # These currently require one to be in the git directory so go there.
      $currentDir = Get-Location
      Set-Location $Directory
    }
    elseif ($Directory) {
      if ($commandParts -eq '-C') {
        # Not an error, git will pick the last one, but unexpected.
        Write-Warning 'Better use either -Directory or -C, not both'
      }
      $Command = "-C $Directory " + $Command
    }
    Write-Verbose "Invoke-Git on '$Directory' with command '$subCommand' ('$Command')"
    $gitRedirection = $env:GIT_REDIRECT_STDERR
    $env:GIT_REDIRECT_STDERR = '2>&1'
    # Deliberately not getting output here: while this means we cannot pass the actual error to Write-Error,
    # it does result in all commands being shown 'live'. Otherwise when doing a clone for instance,
    # nothing gets displayed while git is doing it's thing which is unexepected and too different from normal usage.
    Invoke-Expression "$Git $Command"
    if ($LASTEXITCODE -ne 0) {
      Write-Error "$Git $Command exited with code $LASTEXITCODE"
    }
  }
  finally {
    $env:GIT_REDIRECT_STDERR = $gitRedirection
    if ($currentDir) {
      Set-Location $currentDir
    }
  }
}

<#
.SYNOPSIS
Expand the VAR in ${VAR} (style used by mr) as environment variable.
#>
function ExpandMrStyleVariables {
  param(
    [String] $in
  )
  # Turn ${var} into %var% then use standard function.
  [System.Environment]::ExpandEnvironmentVariables(($in -replace '\$\{([^\}]+)\}', '%$1%'))
}

<#
.SYNOPSIS
Get repository info from .mrconfig-style file
.DESCRIPTION
By default looks for repositories in .mrconfig: this is the file normally used by 'mr'
(http://linux.die.net/man/1/mr), but any text file which contains lines like 'git clone <address> <dir>'
can be used. Expansion of environment variables is supported with ${VARIABLE} syntax.
If such line is followed by another line which has 'git checkout <branch>', then <branch>
is considered to be the inital branch and it will be checked out after cloning.
Returns hash array with remote address, directory and initial branch name.
#>
function Get-MrRepos {
  [CmdletBinding()]
  param (
    [String] $MrConfig = '.\.mrconfig'
  )

  # Not using Resolve-Path here: for network drives this returns e.g.
  # Microsoft.PowerShell.Core\FileSystem::\\server\share\.mrconfig
  # which is a string which only works in PS, not for git.
  $fullMrPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($MrConfig)
  $baseDir = Split-Path $fullMrPath
  $getBranch = {
    param($regexMatch)
    $branch = ($regexMatch.Context.PostContext |
        Select-String -Pattern 'checkout\s+?(\S+)?' |
        ForEach-Object { $_.Matches[0].Groups[1].Value })
    if (-not $branch) {
      'master' 
    }
    else {
      $branch 
    }
  }
  return Select-String $MrConfig -Pattern "^checkout\s+=\s+git\s+clone\s+'?([^']+)'?\s+'?([^']+)'?" -Context (0, 1) |
    ForEach-Object {
      $repository = @{
        'remote' = (ExpandMrStyleVariables $_.Matches[0].Groups[1].Value);
        'name' = (ExpandMrStyleVariables $_.Matches[0].Groups[2].Value);
        'directory' = (ExpandMrStyleVariables $_.Matches[0].Groups[2].Value);
        'branch' = (ExpandMrStyleVariables (& $getBranch $_)) 
      }
      if (-not [IO.Path]::IsPathRooted($repository.directory)) {
        $repository.directory = Join-Path $baseDir $repository.directory
      }
      $repository
    }
}

<#
.SYNOPSIS
Create .mrconfig-style file by listing repositories
.DESCRIPTION
Scan directory for git repositories and dump them in a .mrconfig file usable
by e.g. Get-MrRepos.
#>
function Write-MrConfig {
  [CmdletBinding()]
  param (
    [String] $Directory = '.',
    [String] $MrConfig = '.mrconfig',
    [Int] $Depth = 3,
    [Boolean] $Recurse = $True
  )

  function CreateMrText {
    param($dir, $repo)
    $text = "[$dir]'`n"
    $text += "checkout = git clone '$repo' '$dir'`n"
    $text
  }

  function GetRepositoryInfo {
    param($dirInfo)
    $relativePath = $dirInfo.FullName.Replace($Directory, '').TrimStart('\').Replace('\', '/').Replace('.git', '').TrimEnd('/')
    $subDirs = $relativePath -Split '/'
    [PSCustomObject] @{
      'path' = $dirInfo
      'remote' = (Invoke-Git -Directory $dirInfo.FullName remote get-url origin)
      'relativePath' = $relativePath
      'subDirs' = $subDirs # Just for the sorted looping below; note this will be modified there!
    }
  }

  function LoopSorted {
    param($items)
    $items | Where-Object {$_.subDirs.Count -eq 1} | Sort-Object -Property relativePath # Root items.
    $items = $items | Where-Object {$_.subDirs.Count -gt 1} # The rest.
    $subDirs = $items | ForEach-Object {$_.subDirs[0]} | Get-Unique | Sort-Object # Sort order for the rest.
    foreach ($subDir in $subDirs) {
      LoopSorted ($items | Where-Object {$_.subDirs[0] -eq $subDir} | ForEach-Object {$_.subDirs = $_.subDirs[1..$_.subDirs.Count]; $_})
    }
  }

  $Directory = (Resolve-Path $Directory).Path
  $repos = Get-ChildItem -Recurse:$Recurse -Depth $Depth -Directory -Force -Include '*.git' $Directory |
    Where-Object {($null -ne (Get-ChildItem (Join-Path $_ 'HEAD') -ErrorAction SilentlyContinue))} |
    ForEach-Object {GetRepositoryInfo $_}

  ((LoopSorted $repos) |
    ForEach-Object {"[$($_.relativePath)]`ncheckout = git clone '$($_.remote)' '$($_.relativePath)'`n"}) -Join "`n"
}

<#
.SYNOPSIS
Clone or update a git repository.
.DESCRIPTION
Clone from a git remote into the given directory if the directory doesn't yet exist,
or else update the directory content according to the parameters.

In case of a clone:
- first clones
- if $Branch is specified it is checked out
- else if $UseNewest is true, figures out the newest commit and checks it out
- otherwise the default branch, whichever that may be, is used since that is what clone does

In case of an existing repository:
- if $Branch is specified it is (forcibly, i.e. might discard current changes) checked out
- else if $UseNewest is true, figures out the newest commit and (forcibly) checks it out
- otherwise the current branch is updated using pull --rebase

After each scenario submodules, if any, are updated.
.PARAMETER Directory
Full destination path.
.PARAMETER Remote
Git remote address.
.PARAMETER Branch
Branch to checkout.
.PARAMETER UseNewest
Checkout newest commit.
.PARAMETER Shallow
Perform a Shallow clone (also of submodules).
.PARAMETER Recursive
Use --recursive for submodule init. Separate flag because this might take ages,
whereas you might only need a couple of submodules. There's no good solution for that
now apart from doing it manually.
.PARAMETER Quiet
Add -q to commands.
#>
function Update-GitRepo {
  [CmdletBinding(DefaultParameterSetName = 'Branch')]
  param (
    [Parameter(Mandatory = $True, Position = 0)] [String] $Directory,
    [Parameter(Mandatory = $True, Position = 1)] [String] $Remote,
    [Parameter(ParameterSetName = 'Branch')] $Branch = '',
    [Parameter(ParameterSetName = 'UseNewest')] [Switch] $UseNewest,
    [Switch] $Shallow,
    [Switch] $Recursive,
    [Switch] $Quiet
  )

  function CallGit() {
    param (
      [Parameter(Position = 0, ValueFromRemainingArguments = $True)] [string] $Command
    )
    $thisCommand = $Command
    if ($Quiet) {
      $thisCommand = $thisCommand + ' -q'
    }
    Invoke-Git -Directory $Directory $thisCommand
  }

  if (-not (Test-Path $Directory)) {
    Write-Verbose "$Directory doesn't exist, cloning"
    if ($Shallow) {
      CallGit clone --depth=1 --no-single-branch $Remote
    }
    else {
      CallGit clone $Remote
    }
    if ($Branch) {
      CallGit checkout $Branch
    }
  }
  else {
    Write-Verbose "$Directory is an existing repository"
    if ($Branch) {
      CallGit checkout --force $Branch
    }
    if ($UseNewest) {
      CallGit fetch --depth=1
    }
    else {
      CallGit pull --rebase
    }
  }

  if ($UseNewest) {
    $lastCommit = CallGit 'log -n1 --all --format="%h %d"'
    Write-Verbose "Last commit is $lastCommit"
    CallGit checkout --force $lastCommit.Split(' ')[0]
  }

  if (Test-Path (Join-Path $Directory '.gitmodules')) {
    $command = 'submodule update --init'
    if ($Recursive) {
      $command += ' --recursive'
    }
    if ($Shallow) {
      $command += ' --depth=1'
    }
    CallGit $command
  }
}

<#
.SYNOPSIS
Multiple repository tool for git
.DESCRIPTION
Run git commands on multiple repositories.
By default looks for repositories in .mrconfig, see Get-MrRepos,
or existing repositories to run on can be passed instead.
.PARAMETER Directory
Directory containing the .mrconfig file.
.PARAMETER Repositories
Run on these repositories instead of on a .mrconfig file.
.PARAMETER Table
Output all results in a table instead of printing to output.
Mostly usefule for automation/inspection.
.PARAMETER UseNewest
Checkout newest commit.
.PARAMETER Shallow
If needed to clone, use shallow clone.
.PARAMETER Script
Instead of running $Command, pass all repositories and $Command to this ScriptBlock.
.PARAMETER Command
The git command.
.EXAMPLE
PS C:\> Mr # will clone if needed
PS C:\> Mr -Table status # output table to pipeline, don't use Write-Host
PS C:\> Mr -Script { $Args[0] } # run arbitrary code for each repository, first argument is result from Get-MrRepos, second one the command
PS C:\> Mr pull --rebase
PS C:\> Mr -Repositories a, b, c checkout master
PS C:\> Mr checkout master -Repositories a, b, c
#>
function Invoke-Mr {
  [CmdletBinding(DefaultParameterSetName = 'Directory')]
  param (
    [Parameter(ParameterSetName = 'Repositories')] [String[]] $Repositories = @(),
    [Parameter(ParameterSetName = 'Directory')] [String] $Directory = (Get-Location),
    [Parameter()] [Switch] $Table,
    [Parameter()] [Switch] $Shallow,
    [Parameter()] [ScriptBlock] $Script,
    [Parameter(Position = 0, ValueFromRemainingArguments = $True)] [String] $Command
  )

  if ($PsCmdlet.ParameterSetName -eq 'Directory') {
    $repoObjects = Get-MrRepos -ErrorAction Stop (Join-Path $Directory '.mrconfig')
  }
  else {
    $repoObjects = $Repositories |
      ForEach-Object { @{'remote' = ''; 'directory' = (Resolve-Path -ErrorAction Stop $_); 'branch' = ''} }
  }

  $repoObjects | ForEach-Object {
    if (-not $Table) {
      Write-Host -ForegroundColor cyan '[mr] ' $_.directory
    }
    if ($_.remote) {
      if (-not (Test-Path $_.directory)) {
        if ($Table) {
          $cloneOutput = Update-GitRepo $_.directory $_.remote -Branch $_.branch -Shallow:$Shallow
        }
        else {
          Update-GitRepo $_.directory $_.remote -Branch $_.branch -Shallow:$Shallow
        }
      }
    }
    if ($Script) {
      if ($Table) {
        $gitOutput = & $Script $_ $Command
      }
      else {
        & $Script $_ $Command
      }
    }
    elseif ($Command) {
      if ($Table) {
        $gitOutput = Invoke-Git -Directory $_.directory $Command
      }
      else {
        Invoke-Git -Directory $_.directory $Command
      }
    }
    if ($Table) {
      [PSCustomObject]@{
        'directory' = $_.directory
        'git' = $gitOutput
        'clone' = $cloneOutput
      }
    }
  }
}

New-Alias -Name Mr -Value Invoke-Mr -ErrorAction SilentlyContinue
New-Alias -Name IGit -Value Invoke-Git -ErrorAction SilentlyContinue
