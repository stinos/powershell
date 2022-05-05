Import-Module Pester

BeforeAll {
  . ($PSCommandPath.Replace('.Tests', ''))
}

Describe 'Get-ChildPaths' {
  BeforeEach {
    Mock Get-ChildItem {
      @{FullName = 'bar'}
      @{FullName = 'baz'}
    }
  }
  
  It 'Returns all paths when using default arguments' {
    Get-ChildPaths 'foo' | Should -Be @('bar', 'baz')
  }

  It 'Filters excluded paths' {
    Get-ChildPaths 'foo' -Exclude @('bar', 'baz') | Should -Be @()
    Get-ChildPaths 'foo' -Exclude @('ba?') | Should -Be @()
    Get-ChildPaths 'foo' -Exclude @('bar') | Should -Be @('baz')
  }

  It 'Includes only included paths' {
    Get-ChildPaths 'foo' -Include @('bar', 'baz') | Should -Be @('bar', 'baz')
    Get-ChildPaths 'foo' -Include @('ba?') | Should -Be @('bar', 'baz')
    Get-ChildPaths 'foo' -Include @('bar') | Should -Be @('bar')
  }

  It 'Filters on logical and of Include and Exclude' {
    Get-ChildPaths 'foo' -Include @('bar', 'baz') -Exclude 'ba*' | Should -Be @()
    Get-ChildPaths 'foo' -Include @('ba?') -Exclude @('something', '*r') | Should -Be @('baz')
  }

  It 'Skips directories with File switch' {
    Mock Get-ChildItem {
      @{FullName = 'bar'; PSIsContainer = $True}
      @{FullName = 'baz'; PSIsContainer = $False}
    }
    Get-ChildPaths -File 'foo' | Should -Be @('baz')
  }
}

Describe 'Split-Array' {
  It 'Returns empty array when no input' {
    Split-Array @() -ChunkSize 1 | Should -Be (, @())
    # Note: this one doesn't even run the process block, but does run the end block.
    @() | Split-Array -ChunkSize 1 | Should -Be (, @())
  }

  It 'Splits in chunks' {
    Split-Array @(1, 2) -ChunkSize 1 | Should -Be @(@(1), @(2))
    Split-Array @(1, 2) -ChunkSize 2 | Should -Be @(, @(1, 2))
    Split-Array @(1, 2, 3, 4) -ChunkSize 3 | Should -Be @(@(1, 2, 3), , @(4))
    @(1, 2) | Split-Array -ChunkSize 1 | Should -Be @(@(1), @(2))
    @(1, 2) | Split-Array -ChunkSize 2 | Should -Be @(, @(1, 2))
    @(1, 2, 3, 4) | Split-Array -ChunkSize 3 | Should -Be @(@(1, 2, 3), , @(4))
  }
}
