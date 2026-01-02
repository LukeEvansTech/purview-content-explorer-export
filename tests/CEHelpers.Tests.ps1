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
