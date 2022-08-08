Import-Module Pester

BeforeAll {
  . ($PSCommandPath.Replace('.Tests', ''))
}

Describe 'ExpandMrStyleVariables' {
  It 'Expands ${} style environment variables' {
    # Don't know which variables are guaranteed to be available,
    # adding/removing while taking care not to overwrite is too much effort to be worth it,
    # so just take the first variable available.
    $variable = Get-ChildItem Env: | Select-Object -First 1
    ExpandMrStyleVariables 'foo ${VAR} bar ${VAR}'.Replace('VAR', $variable.Name) |
      Should -Be 'foo VAR bar VAR'.Replace('VAR', $variable.Value)
  }

  It 'Does not touch empty ${} or ${ without closing brace' {
    ExpandMrStyleVariables 'foo ${} ${bar' | Should -Be 'foo ${} ${bar'
  }
}
