Import-Module Pester

BeforeAll {
  . ($PSCommandPath.Replace('.Tests', ''))
}

Describe 'Test-NotLike' {
  It 'Works like -notlike $null with no arguments' {
    Test-NotLike '' | Should -Be $False
    Test-NotLike 'a' | Should -Be $True
  }

  It 'Works like ($arg -notlike $val1) with 1 argument' {
    Test-NotLike '' '' | Should -Be $False
    Test-NotLike 'a' 'b' | Should -Be $True
    Test-NotLike '' @($null) | Should -Be $False
    Test-NotLike 'a' @('b') | Should -Be $True
    Test-NotLike 'a' @('*') | Should -Be $False
  }

  It 'Works like ($arg -notlike $val1) -and ($arg -notlike $val2) ... with arguments' {
    Test-NotLike '' @('a', '') | Should -Be $False
    Test-NotLike '' @('a', 'b') | Should -Be $True
    Test-NotLike 'aa' @('a', 'b', 'c') | Should -Be $True
    Test-NotLike 'aa' @('a', 'aa') | Should -Be $False
    Test-NotLike 'abc' @('a?c') | Should -Be $False
    Test-NotLike 'abc' @('a*c') | Should -Be $False
  }
}

Describe 'Test-Like' {
  It 'Works like -notlike $null with no arguments' {
    Test-Like '' | Should -Be $True
    Test-Like 'a' | Should -Be $False
  }

  It 'Works like ($arg -like $val1) with 1 argument' {
    Test-Like '' '' | Should -Be $True
    Test-Like 'a' 'b' | Should -Be $False
    Test-Like '' @($null) | Should -Be $True
    Test-Like 'a' @('b') | Should -Be $False
    Test-Like 'abc' @('a?c') | Should -Be $True
    Test-Like 'abc' @('a*c') | Should -Be $True
  }

  It 'Works like ($arg -like $val1) -and ($arg -like $val2) ... with arguments' {
    Test-Like '' @('a', '') | Should -Be $True
    Test-Like '' @('a', 'b') | Should -Be $False
    Test-Like 'aa' @('a', 'b', 'c') | Should -Be $False
    Test-Like 'aa' @('a', 'aa') | Should -Be $True
    Test-Like 'abc' @('d', 'a*c') | Should -Be $True

  }
}
