# Run with: Invoke-Pester ./tests/CEHelpers.Tests.ps1
BeforeAll {
    Import-Module "$PSScriptRoot/../lib/CEHelpers.psm1" -Force
}

Describe 'Get-CESafeName' {
    It 'leaves alphanumeric, dot, underscore, hyphen unchanged' {
        Get-CESafeName 'Credit-Card_v2.0' | Should -Be 'Credit-Card_v2.0'
    }
    It 'replaces spaces with underscores' {
        Get-CESafeName 'Credit Card Number' | Should -Be 'Credit_Card_Number'
    }
    It 'replaces forward slash with underscore' {
        Get-CESafeName 'Credit/Debit Card' | Should -Be 'Credit_Debit_Card'
    }
    It 'replaces multiple unsafe chars individually (no collapsing)' {
        Get-CESafeName 'A  B' | Should -Be 'A__B'
    }
    It 'handles unicode by replacing with underscore' {
        Get-CESafeName 'Café' | Should -Be 'Caf_'
    }
    It 'returns empty string for empty input' {
        Get-CESafeName '' | Should -Be ''
    }
}

Describe 'Test-CETagNameFilter' {
    It 'returns true when NameLike matches and NameNotLike empty' {
        Test-CETagNameFilter -Name 'Credit Card' -NameLike @('Credit*') -NameNotLike @() | Should -BeTrue
    }
    It 'returns false when no NameLike pattern matches' {
        Test-CETagNameFilter -Name 'Credit Card' -NameLike @('SSN*') -NameNotLike @() | Should -BeFalse
    }
    It 'returns false when any NameNotLike pattern matches' {
        Test-CETagNameFilter -Name 'Credit Card' -NameLike @('*') -NameNotLike @('Credit*') | Should -BeFalse
    }
    It 'matches when ANY NameLike pattern matches (OR semantics)' {
        Test-CETagNameFilter -Name 'SSN' -NameLike @('Credit*','SSN*') -NameNotLike @() | Should -BeTrue
    }
    It 'is case-insensitive for include' {
        Test-CETagNameFilter -Name 'CREDIT CARD' -NameLike @('credit*') -NameNotLike @() | Should -BeTrue
    }
    It 'is case-insensitive for exclude' {
        Test-CETagNameFilter -Name 'credit card' -NameLike @('*') -NameNotLike @('CREDIT*') | Should -BeFalse
    }
    It 'defaults to match-all when NameLike is empty array' {
        Test-CETagNameFilter -Name 'anything' -NameLike @() -NameNotLike @() | Should -BeTrue
    }
}
