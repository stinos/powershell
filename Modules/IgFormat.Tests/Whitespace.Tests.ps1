Import-Module Pester

BeforeAll {
  . ($PSCommandPath.Replace('.Tests', ''))

  [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredvarsMoreThanAssignments', 'rules')]
  $rules = @(
    (New-WhitespaceRule @(
      '.a',
      '.b'
    )),
    (New-WhitespaceRule -CrLf -Encoding 'utf8' -NoNewLineAtEndOfFile @(
      '.c'
    )),
    (New-WhitespaceRule -Ignore @(
      '.d'
    ))
  )
}

Describe 'Format-WhitespaceRules' {

  BeforeEach {
    Mock 'Test-WhitespaceAndEncoding'
    Mock 'Write-WhitespaceAndEncoding'
  }

  It 'Skips files without rules' {
    Format-WhitespaceRules -WhitespaceRules $rules '.e' |
      Should -Not -Invoke 'Test-WhitespaceAndEncoding' |
      Should -Not -Invoke 'Write-WhitespaceAndEncoding'
  }

  It 'Skips ignored files' {
    Format-WhitespaceRules -WhitespaceRules $rules '.d' |
      Should -Not -Invoke 'Test-WhitespaceAndEncoding' |
      Should -Not -Invoke 'Write-WhitespaceAndEncoding'
  }

  It 'Lists files without rules' {
    Format-WhitespaceRules -WhitespaceRules $rules -ListMissing @('.a', '.d', '.e', '.f') |
      Should -Be @('.e', '.f') |
      Should -Not -Invoke 'Test-WhitespaceAndEncoding' |
      Should -Not -Invoke 'Write-WhitespaceAndEncoding'
  }

  It 'Writes files with rules' {
    Format-WhitespaceRules -WhitespaceRules $rules @('1.a', '2.b', '3.c')
    Should -Invoke 'Write-WhitespaceAndEncoding' -Exactly 1 -ParameterFilter {
      $File -eq '1.a' -and $CrLF -eq $False -and $Encoding -eq 'ascii' -and $NewLineAtEndOfFile -eq $True
    }
    Should -Invoke 'Write-WhitespaceAndEncoding' -Exactly 1 -ParameterFilter {
      $File -eq '2.b' -and $CrLF -eq $False -and $Encoding -eq 'ascii' -and $NewLineAtEndOfFile -eq $True
    }
    Should -Invoke 'Write-WhitespaceAndEncoding' -Exactly 1 -ParameterFilter {
      $File -eq '3.c' -and $CrLF -eq $True -and $Encoding -eq 'utf8' -and $NewLineAtEndOfFile -eq $False
    }
    Should -Not -Invoke 'Test-WhitespaceAndEncoding'
  }

  It 'Tests files with rules' {
    Format-WhitespaceRules -WhitespaceRules $rules -Test @('1.a', '2.b', '3.c')
    Should -Invoke 'Test-WhitespaceAndEncoding' -Exactly 1 -ParameterFilter {
      $File -eq '1.a' -and $CrLF -eq $False -and $Encoding -eq 'ascii' -and $NewLineAtEndOfFile -eq $True
    }
    Should -Invoke 'Test-WhitespaceAndEncoding' -Exactly 1 -ParameterFilter {
      $File -eq '2.b' -and $CrLF -eq $False -and $Encoding -eq 'ascii' -and $NewLineAtEndOfFile -eq $True
    }
    Should -Invoke 'Test-WhitespaceAndEncoding' -Exactly 1 -ParameterFilter {
      $File -eq '3.c' -and $CrLF -eq $True -and $Encoding -eq 'utf8' -and $NewLineAtEndOfFile -eq $False
    }
    Should -Not -Invoke 'Write-WhitespaceAndEncoding'
  }

  It 'Returns test output then fails' {
    Mock 'Test-WhitespaceAndEncoding' {
      "fail $File"
    }
    Format-WhitespaceRules -WhitespaceRules $rules -Test @('1.a', '2.b', '3.c') -ErrorAction SilentlyContinue -ErrorVariable 'werr' |
      Should -Be @('fail 1.a', 'fail 2.b', 'fail 3.c')
    $werr.Exception.Message | Should -Be 'Found whitespace/encoding mismatches'
    Should -Not -Invoke 'Write-WhitespaceAndEncoding'
  }
}
