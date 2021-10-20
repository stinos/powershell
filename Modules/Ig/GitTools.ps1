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
  try {
    $commandParts = $Command.Split(' ')
    $subCommand = $commandParts[0]
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
Get repository info from .mrconfig-style file
.DESCRIPTION
By default looks for repositories in .mrconfig: this is the file normally used by 'mr'
(http://linux.die.net/man/1/mr), but any text file which contains lines like 'git clone <address> <dir>' can be used.
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
      @{ 'remote' = $_.Matches[0].Groups[1].Value;
        'name' = $_.Matches[0].Groups[2].Value;
        'directory' = (Join-Path $baseDir $_.Matches[0].Groups[2].Value);
        'branch' = (& $getBranch $_) 
      } }
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
This will clone from a git remote into the given directory if the directory doesn't yet exist,
or else update the directory content according to the parameters.

In case of a clone:
- first clones
- if a branch is specified it is checked out
- if no branch specified but UseNewest is true, figures out the newest commit and (forcibly) checks it out

In case of an existing repository and specific branch:
- if ChangeBranch is true the branch is (forcibly) checked out
- if UpdateBranch is true the branch is updated using pull --rebase

In case of an existing repository and no specific branch:
- if UpdateBranch is true the branch is updated using pull --rebase
- else if UseNewest is true, figures out the newest commit and (forcibly) checks it out

After each scenario submodules, if any, are updated.
.PARAMETER Directory full destination path
.PARAMETER Remote git remote address
.PARAMETER Branch branch to checkout
.PARAMETER ChangeBranch change to Branch if repo exists already
.PARAMETER UpdateBranch pull current or new branch
.PARAMETER UseNewest checkout newest commit
.PARAMETER Shallow do a Shallow clone
.PARAMETER Quiet add -q to commands
#>
function Update-GitRepo {
  param (
    [Parameter(Mandatory = $True)] [String] $Directory,
    [Parameter(Mandatory = $True)] [String] $Remote,
    [String] $Branch = '',
    [Boolean] $ChangeBranch = $True,
    [Boolean] $UpdateBranch = $True,
    [Boolean] $UseNewest = $False,
    [Boolean] $Shallow = $False,
    [Boolean] $Quiet = $False
  )

  if ($UseNewest) {
    $UpdateBranch = $False
  }
  $needsCheckout = -not ($Branch -eq '')

  function callgit() {
    if ($Quiet) {
      $args = '-q ' + $args
    }
    Invoke-Git -Directory $Directory $args
  }

  if (-not (Test-Path $Directory)) {
    if ($Shallow) {
      # Note appveyor's git doesn't yet have '--Shallow-submodules'
      callgit clone --depth=1 --no-single-branch $Remote
    }
    else {
      Invoke-Git -Directory $Directory clone $Remote
    }
    if ($needsCheckout -and -not ($Branch -eq 'master')) {
      Invoke-Git -Directory $Directory checkout $Branch
    }
  }
  else {
    Write-Verbose "$Directory is an existing repository"
    if ($needsCheckout -and $ChangeBranch) {
      callgit checkout --force $Branch
    }
    if ($UpdateBranch) {
      callgit pull --rebase
    }
    elseif ($UseNewest) {
      callgit fetch --depth=1
    }
  }

  if ($UseNewest) {
    $lastCommit = Invoke-Git -Directory $Directory 'log -n1 --all --format="%h %d"'
    Write-Verbose ('[{0}]' -f $lastCommit)
    callgit checkout --force $lastCommit.Split(' ')[0]
  }

  if (($UpdateBranch -or $UseNewest) -and (Test-Path (Join-Path $Directory '.gitmodules'))) {
    # Still need to figure out how to Shallow clone these
    callgit submodule update --init --recursive
  }
}

<#
.SYNOPSIS
Clone repository if it does not yet exist.
.DESCRIPTION
Takes input as returned by Get-MrRepos.
#>
function Invoke-CloneIfNeeded {
  param (
    [Parameter(Mandatory)] [Object[]] $repo
  )

  Update-GitRepo $repo.directory $repo.remote $repo.branch -UpdateBranch $False -ChangeBranch $False -UseNewest $False -Shallow $False
}

<#
.SYNOPSIS
Multiple repository tool for git
.DESCRIPTION
Run git commands on multiple repositories.
By default looks for repositories in .mrconfig, see Get-MrRepos,
or existing repositories to run on can be passed instead.
.EXAMPLE
PS C:\> Mr # will clone if needed
PS C:\> Mr -Table status # output table to pipeline, don't use Write-Host
PS C:\> Mr -Script { $Args[0] } # run arbitrary code for each repository, first argument is result from Get-MrRepos, second one the command
PS C:\> Mr pull --rebase
PS C:\> Mr -Repositories a, b, c checkout master
PS C:\> Mr checkout master -Repositories a, b, c
#>
function Invoke-Mr {
  param (
    [Parameter()] [String[]] $Repositories = @(),
    [Parameter()] [String] $Directory = (Get-Location),
    [Parameter()] [Switch] $Table,
    [Parameter()] [ScriptBlock] $Script,
    [Parameter(Position = 0, ValueFromRemainingArguments = $True)] [String] $Command
  )

  if ($Repositories.Count -eq 0) {
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
      if ($Table) {
        $cloneOutput = Invoke-CloneIfNeeded $_
      }
      else {
        Invoke-CloneIfNeeded $_
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
