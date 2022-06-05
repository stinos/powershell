Import-Module Pester

BeforeAll {
  . ($PSCommandPath.Replace('.Tests', ''))

  function FormatA {
    param($Items, $Check, $Arguments)
  }

  function FormatB {
    param($Items, $Check, $Arguments)
  }

  function FormatC {
    param($Items, $Check, $Arguments)
  }

  # For convenience of writing tests we write '\' in the tests themselves,
  # the correct it for the platform when comparing.
  function SamePaths {
    $a = $Args[0] | ForEach-Object {$_.Replace('\', [IO.Path]::DirectorySeparatorChar)}
    $b = $Args[1] | ForEach-Object {$_.Replace('\', [IO.Path]::DirectorySeparatorChar)}
    -not (Compare-Object $a $b -SyncWindow 0)
  }

  $fmtA = New-CodeFormatter('fmtA')
  $fmtA.Command = {FormatA @Args}
  $fmtA.Paths = @('A')
  $fmtA.Exclusions = @((Join-Path 'A' 'B*'))
  $fmtA.Extensions = @('.a', '.aa')
  $fmtA.TakesArguments = $True
  $fmtA.ApplyDefaultArguments = {
    param($value)
    if ($value.Count -eq 0) {
      2
    } else {
      $value
    }
  }

  $fmtB = New-CodeFormatter('fmtB')
  $fmtB.Command = {FormatB @Args}
  $fmtB.Paths = @('A', 'B')
  $fmtB.Extensions = @('.b')

  $fmtC = New-CodeFormatter('fmtC')
  $fmtC.Command = {FormatC @Args}
  $fmtC.Paths = @('A')
  $fmtC.Exclusions = @('*.a')
  $fmtC.Extensions = @('.*')
  $fmtC.OnByDefault = $False
  $fmtC.ListFiles = {
    (Join-Path $Args[0] 'foo.a')
    (Join-Path $Args[0] 'foo.b')
    (Join-Path $Args[0] 'foo.c')
  }

  [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredvarsMoreThanAssignments', 'formatters')]
  $formatters = @($fmtA, $fmtB, $fmtC)
}

Describe 'Format-Code' {

  Context 'Listing files' {

    BeforeEach {
      InModuleScope 'Ig' {
        Mock 'Get-ChildItem' -ParameterFilter {$Path -eq (Join-Path '.' 'A')} {
          @{FullName = (Join-Path 'A' 'foo.a')}
          @{FullName = (Join-Path 'A' 'foo.aa')}
          @{FullName = (Join-Path 'A' 'foo.b')}
          @{FullName = (Join-Path 'A' (Join-Path 'B' 'foo.a'))}
          @{FullName = (Join-Path 'A' (Join-Path 'B' 'foo.b'))}
        }
        Mock 'Get-ChildItem' -ParameterFilter {$Path -eq (Join-Path '.' 'B')} {
          @{FullName = (Join-Path 'B' 'foo.a')}
          @{FullName = (Join-Path 'B' 'foo.b')}
        }
      }
      Mock 'Test-Path' {
        $False
      }
    }

    It 'Filters on path and extension' {
      Mock 'FormatA'
      Format-Code -Formatters $formatters
      Should -Invoke 'FormatA' -Exactly 1 -ParameterFilter {
        SamePaths $Items @('A\foo.a', 'A\foo.aa')
      }
    }

    It 'Batches on paths' {
      Mock 'FormatB'
      Format-Code -Formatters $formatters
      Should -Invoke 'FormatB' -Exactly 1 -ParameterFilter {
        SamePaths $Items @('A\foo.b', 'A\B\foo.b')
      }
      Should -Invoke 'FormatB' -Exactly 1 -ParameterFilter {
        SamePaths $Items @('B\foo.b')
      }
    }

    It 'Overrides formatter paths with argument paths which can also be files' {
      InModuleScope 'Ig' {
        Mock 'Get-ChildItem' -ParameterFilter {$Path -eq 'C'} {
          @{FullName = 'C\foo.a'}
          @{FullName = 'C\foo.b'}
        }
      }
      Mock 'Test-Path' -ParameterFilter {$LiteralPath -ne 'C'} {
        $True
      }
      Mock 'FormatA'
      Mock 'FormatB'
      Format-Code -Formatters $formatters -Paths @('a.a', 'a.b', 'C')
      Should -Invoke 'FormatA' -Exactly 1 -ParameterFilter {
        SamePaths $Items @('a.a')
      }
      Should -Invoke 'FormatA' -Exactly 1 -ParameterFilter {
        SamePaths $Items @('C\foo.a')
      }
      Should -Invoke 'FormatB' -Exactly 1 -ParameterFilter {
        SamePaths $Items @('a.b')
      }
      Should -Invoke 'FormatB' -Exactly 1 -ParameterFilter {
        SamePaths $Items @('C\foo.b')
      }
    }

    It 'Can use a different file root' {
      InModuleScope 'Ig' {
        Mock 'Get-ChildItem' -ParameterFilter {$Path -eq (Join-Path 'root' 'A')} {
          @{FullName = 'foo.a'}
        }
        Mock 'Get-ChildItem' -ParameterFilter {$Path -eq (Join-Path 'root' 'B')} {
          @{FullName = 'foo.b'}
        }
      }
      Mock 'FormatA'
      Mock 'FormatB'
      Format-Code -Formatters $formatters -FileRoot 'root'
      Should -Invoke 'FormatA' -Exactly 1 -ParameterFilter {
        SamePaths $Items @('foo.a')
      }
      Should -Invoke 'FormatB' -Exactly 1 -ParameterFilter {
        SamePaths $Items @('foo.b')
      }
    }

    It 'Does not use file root on argument paths' {
      Mock 'FormatA'
      Mock 'FormatB'
      Format-Code -Formatters $formatters -FileRoot 'root' -Paths @((Join-Path '.' 'A'))
      Should -Invoke 'FormatA' -Exactly 1 -ParameterFilter {
        SamePaths $Items @('A\foo.a', 'A\foo.aa')
      }
      Should -Invoke 'FormatB' -Exactly 1 -ParameterFilter {
        SamePaths $Items @('A\foo.b', 'A\B\foo.b')
      }
    }

    It 'Takes paths from pipeline' {
      Mock 'FormatA'
      Mock 'FormatB'
      (Join-Path '.' 'B') | Format-Code -Formatters $formatters
      Should -Invoke 'FormatA' -Exactly 1 -ParameterFilter {
        SamePaths $Items @('B\foo.a')
      }
      Should -Invoke 'FormatB' -Exactly 1 -ParameterFilter {
        SamePaths $Items @('B\foo.b')
      }
    }

    It 'Can use custom listing' {
      Mock 'FormatC'
      Format-Code -Formatters $formatters -NofmtA -NofmtB -fmtC
      Should -Invoke 'FormatC' -Exactly 1 -ParameterFilter {
        SamePaths $Items @('.\A\foo.b', '.\A\foo.c')
      }
    }
  }

  Context 'Calling commands' {

    BeforeEach {
      InModuleScope 'Ig' {
        Mock 'Get-ChildItem' {
          @{FullName = 'A\foo.a'}
          @{FullName = 'A\foo.b'}
        }
      }
    }

    It 'Passes Check argument through' {
      Mock 'FormatA'
      Mock 'FormatB'
      Format-Code -Formatters $formatters |
        Should -Invoke 'FormatA' -Times 1 -ParameterFilter {$Check -eq $False} |
        Should -Invoke 'FormatB' -Times 1 -ParameterFilter {$Check -eq $False}
      Format-Code -Formatters $formatters -Check |
        Should -Invoke 'FormatA' -Times 1 -ParameterFilter {$Check -eq $True} |
        Should -Invoke 'FormatB' -Times 1 -ParameterFilter {$Check -eq $True}
    }

    It 'Passes arbitrary formatter arguments' {
      # See https://github.com/pester/Pester/pull/1855: 'Arguments' cannot be used in
      # filter so do this manually.
      Mock 'FormatA' {
        param($Items, $Check, $Arguments)
        Set-Variable -Scope Script -name 'extraArguments' -Value $Arguments
      }
      Format-Code -Formatters $formatters -fmtAArgs 1
      $extraArguments | Should -Be 1
      Format-Code -Formatters $formatters
      $extraArguments | Should -Be 2
    }
  }

  Context 'Selecting formatters' {

    BeforeEach {
      InModuleScope 'Ig' {
        Mock 'Get-ChildItem' {
          @{FullName = 'A\foo.a'}
          @{FullName = 'A\foo.b'}
        }
      }
    }

    It 'Selects default formatters' {
      Mock 'FormatA'
      Mock 'FormatB'
      Mock 'FormatC'
      Format-Code -Formatters $formatters |
        Should -Invoke 'FormatA' -Times 1 |
        Should -Invoke 'FormatB' -Times 1 |
        Should -Invoke 'FormatC' -Times 0
    }

    It 'Selects by arguments' {
      Mock 'FormatA'
      Mock 'FormatB'
      Mock 'FormatC'
      Format-Code -Formatters $formatters -fmtA |
        Should -Invoke 'FormatA' -Times 1 |
        Should -Invoke 'FormatB' -Times 0 |
        Should -Invoke 'FormatC' -Times 0
      Format-Code -Formatters $formatters -fmtB |
        Should -Invoke 'FormatA' -Times 1 |
        Should -Invoke 'FormatB' -Times 1 |
        Should -Invoke 'FormatC' -Times 0
      Format-Code -Formatters $formatters -fmtC |
        Should -Invoke 'FormatA' -Times 1 |
        Should -Invoke 'FormatB' -Times 1 |
        Should -Invoke 'FormatC' -Times 1
    }

    It 'Deselects by arguments' {
      Mock 'FormatA'
      Mock 'FormatB'
      Mock 'FormatC'
      Format-Code -Formatters $formatters -NofmtA -NofmtB |
        Should -Invoke 'FormatA' -Exactly 0 |
        Should -Invoke 'FormatB' -Exactly 0 |
        Should -Invoke 'FormatC' -Exactly 0
      Format-Code -Formatters $formatters -NofmtA |
        Should -Invoke 'FormatA' -Exactly 0 |
        Should -Invoke 'FormatB' -Times 1 |
        Should -Invoke 'FormatC' -Exactly 0
      Format-Code -Formatters $formatters -NofmtB |
        Should -Invoke 'FormatA' -Times 1 |
        Should -Invoke 'FormatB' -Times 1 |
        Should -Invoke 'FormatC' -Exactly 0
    }
  }

  Context 'Generating errors' {

    BeforeEach {
      InModuleScope 'Ig' {
        Mock 'Get-ChildItem' {
          @{FullName = 'A\foo.a'}
          @{FullName = 'A\foo.B'}
        }
      }

      Mock 'FormatA' {
        Write-Error 'failA'
      }

      Mock 'FormatB' {
        Write-Error 'failB'
      }
    }

    It 'Handles errors normally' {
      {Format-Code -Formatters $formatters -ErrorAction Stop} |
        Should -Throw 'failA' |
        Should -Not -Invoke 'FormatB'
    }

    It 'Yields extra message when Check is True' {
      Format-Code -Formatters $formatters -Check -ErrorAction SilentlyContinue -ErrorVariable 'fmtErrors'
      $fmtErrors[0].Exception.Message | Should -Be 'failA'
      $fmtErrors[1].Exception.Message | Should -Be 'failB'
      $fmtErrors[-1].Exception.Message | Should -Be 'Code formatting check failed'
    }
  }
}
