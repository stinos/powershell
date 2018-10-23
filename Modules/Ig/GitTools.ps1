. (Join-Path (Split-Path $PSCommandPath) Tools.ps1)

<#
.SYNOPSIS
Run git commands on specified repository.
#>
function Invoke-Git {
 param (
    [Parameter(Mandatory, Position = 0)] [String] $Directory,
    [Parameter(Position = 1, ValueFromRemainingArguments = $True)] [String[]] $Command
  )

  Write-Verbose "Invoke-Git on '$Directory' with command '$Command'"
  if($Command.Length -gt 0) {
    $subCommand = $Command[0]
  }
  else {
    $subCommand = $Null
  }
  if($subCommand -eq 'clone') {
    Invoke-External { git $Command $Directory }
  }
  elseif($subCommand -eq 'submodule' -or $subCommand -eq 'stash') {
    $currentDir = Get-Location
    cd $Directory
    try {
      Invoke-External { git $Command }
    }
    finally {
      cd $currentDir
    }
  }
  else {
    Invoke-External { git --git-dir=$Directory\.git --work-tree=$Directory $Command }
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
  param (
    [ValidateScript({Test-Path $_})] [String] $MrConfig = '.\.mrconfig'
  )

  $baseDir = Split-Path (Resolve-Path $MrConfig)
  $getBranch = {
    param($regexMatch)
    $branch = ($regexMatch.Context.PostContext | sls -pattern 'checkout\s+?(\S+)?' | %{ $_.Matches[0].Groups[1].Value })
    if(-not $branch) { 'master' } else { $branch }
  }
  return sls $MrConfig -Pattern "^checkout\s+=\s+git\s+clone\s+'?([^']+)'?\s+'?([^']+)'?" -Context (0, 1) |
    % { @{ 'remote' = $_.Matches[0].Groups[1].Value;
           'name' = $_.Matches[0].Groups[2].Value;
           'directory' = (Join-Path $baseDir $_.Matches[0].Groups[2].Value);
           'branch' = (& $getBranch $_) } }
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
    [Parameter(Mandatory=$True)] [String] $Directory,
    [Parameter(Mandatory=$True)] [String] $Remote,
    [String] $Branch = '',
    [Boolean] $ChangeBranch = $True,
    [Boolean] $UpdateBranch = $True,
    [Boolean] $UseNewest = $False,
    [Boolean] $Shallow = $False,
    [Boolean] $Quiet = $False
  )

  if($UseNewest) {
    $UpdateBranch = $False
  }
  $needsCheckout = -not ($Branch -eq '')

  $callgit = {
    if($Quiet) {
      $args += '-q'
    }
    Invoke-Git $Directory -Command $args
  }

  if(-not (Test-Path $Directory)) {
    if($Shallow) {
      # Note appveyor's git doesn't yet have '--Shallow-submodules'
      & $callgit clone --depth=1 --no-single-branch $Remote
    }
    else {
      & $callgit clone $Remote
    }
    if($needsCheckout -and -not ($Branch -eq 'master')){
      & $callgit checkout $Branch
    }
  }
  else {
    Write-Verbose "$Directory is an existing repository"
    if($needsCheckout -and $ChangeBranch){
      & $callgit checkout --force $Branch
    }
    if($UpdateBranch) {
      & $callgit pull --rebase
    }
    elseif($UseNewest) {
      & $callgit fetch --depth=1
    }
  }

  if($UseNewest){
    $lastCommit = Invoke-Git $Directory -Command  log, -n1, --all, --format="%h %d"
    Write-Verbose ('[{0}]' -f $lastCommit)
    & $callgit checkout --force $lastCommit.Split(' ')[0]
  }

  if(($UpdateBranch -or $UseNewest) -and (Test-Path (Join-Path $Directory '.gitmodules'))) {
    # Still need to figure out how to Shallow clone these
    & $callgit submodule update --init --recursive
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
    [Parameter(Position = 0, ValueFromRemainingArguments = $True)] [String[]] $Command
  )

  if($Repositories.Count -eq 0) {
    $repoObjects = Get-MrRepos (Join-Path $Directory '.mrconfig')
  }
  else {
    $repoObjects =  $Repositories | %{ @{'remote' = ''; 'directory' = (Resolve-Path $_); 'branch' = ''} }
  }

  $repoObjects | % {
    if (-not $Table) {
      Write-Host -ForegroundColor cyan '[mr] ' $_.directory
    }
    if ($Table) {
      $cloneOutput = Invoke-CloneIfNeeded $_
    } else {
      Invoke-CloneIfNeeded $_
    }
    if ($Script) {
      if ($Table) {
        $gitOutput = & $Script $_ $Command
      } else {
        & $Script $_ $Command
      }      
    } elseif ($Command.Count -gt 0) {
      if ($Table) {
        $gitOutput = Invoke-Git $_.directory -Command $Command
      } else {
        Invoke-Git $_.directory -Command $Command
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

New-Alias -Name Mr -Value Invoke-Mr
New-Alias -Name IGit -Value Invoke-Git
