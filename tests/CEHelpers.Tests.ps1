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
        # Build the accented name from an ASCII escape so this source file stays pure ASCII
        # (a literal non-ASCII char would trip PSUseBOMForUnicodeEncodedFile, and we
        # deliberately ship these scripts BOM-less so the Unix shebang keeps working).
        Get-CESafeName ('Caf' + [char]0x00E9) | Should -Be 'Caf_'
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

Describe 'Get-CETagTypeEnumeration' {
    It 'returns SensitiveInformationType mapping' {
        $m = Get-CETagTypeEnumeration -TagType SensitiveInformationType
        $m.Cmdlet | Should -Be 'Get-DlpSensitiveInformationType'
        $m.NameProperty | Should -Be 'Name'
    }
    It 'returns Sensitivity mapping' {
        $m = Get-CETagTypeEnumeration -TagType Sensitivity
        $m.Cmdlet | Should -Be 'Get-Label'
        $m.NameProperty | Should -Be 'DisplayName'
    }
    It 'returns Retention mapping' {
        $m = Get-CETagTypeEnumeration -TagType Retention
        $m.Cmdlet | Should -Be 'Get-ComplianceTag'
        $m.NameProperty | Should -Be 'Name'
    }
    It 'returns TrainableClassifier mapping' {
        $m = Get-CETagTypeEnumeration -TagType TrainableClassifier
        $m.Cmdlet | Should -Be 'Get-DlpTrainableClassifier'
        $m.NameProperty | Should -Be 'Name'
    }
    It 'throws on unknown TagType' {
        { Get-CETagTypeEnumeration -TagType 'Bogus' } | Should -Throw
    }
}

Describe 'Get-CEConfidenceSummary' {
    # GUIDs used across the SensitiveInfoTypesData fixtures.
    BeforeAll {
        $script:g1 = '11111111-1111-1111-1111-111111111111'
        $script:g2 = '22222222-2222-2222-2222-222222222222'
        $script:g3 = '33333333-3333-3333-3333-333333333333'
    }

    Context 'ItemMaxConfidence (highest bucket across all SITs in the item)' {
        It 'is 3-High when any SIT has a high-confidence match' {
            $data = "[{`"Id`":`"$g1`",`"LowConfidenceMatch`":9,`"MediumConfidenceMatch`":0,`"HighConfidenceMatch`":0},{`"Id`":`"$g2`",`"LowConfidenceMatch`":4,`"MediumConfidenceMatch`":4,`"HighConfidenceMatch`":2}]"
            (Get-CEConfidenceSummary -Data $data).ItemMaxConfidence | Should -Be '3-High'
        }
        It 'is 2-Medium when the strongest is medium' {
            $data = "[{`"Id`":`"$g1`",`"LowConfidenceMatch`":9,`"MediumConfidenceMatch`":0,`"HighConfidenceMatch`":0},{`"Id`":`"$g2`",`"LowConfidenceMatch`":4,`"MediumConfidenceMatch`":4,`"HighConfidenceMatch`":0}]"
            (Get-CEConfidenceSummary -Data $data).ItemMaxConfidence | Should -Be '2-Medium'
        }
        It 'is 1-Low when the strongest is low' {
            $data = "[{`"Id`":`"$g1`",`"LowConfidenceMatch`":3,`"MediumConfidenceMatch`":0,`"HighConfidenceMatch`":0}]"
            (Get-CEConfidenceSummary -Data $data).ItemMaxConfidence | Should -Be '1-Low'
        }
        It 'is 0-None when every bucket is zero' {
            $data = "[{`"Id`":`"$g1`",`"LowConfidenceMatch`":0,`"MediumConfidenceMatch`":0,`"HighConfidenceMatch`":0}]"
            (Get-CEConfidenceSummary -Data $data).ItemMaxConfidence | Should -Be '0-None'
        }
    }

    Context 'TargetConfidence (confidence of the swept SIT, by GUID)' {
        It 'is the matched GUID''s level when present' {
            $data = "[{`"Id`":`"$g1`",`"LowConfidenceMatch`":9,`"MediumConfidenceMatch`":9,`"HighConfidenceMatch`":0},{`"Id`":`"$g2`",`"LowConfidenceMatch`":4,`"MediumConfidenceMatch`":0,`"HighConfidenceMatch`":0}]"
            (Get-CEConfidenceSummary -Data $data -TargetGuid $g1).TargetConfidence | Should -Be '2-Medium'
            (Get-CEConfidenceSummary -Data $data -TargetGuid $g2).TargetConfidence | Should -Be '1-Low'
        }
        It 'matches the GUID case-insensitively' {
            $data = "[{`"Id`":`"$g1`",`"LowConfidenceMatch`":1,`"MediumConfidenceMatch`":1,`"HighConfidenceMatch`":1}]"
            (Get-CEConfidenceSummary -Data $data -TargetGuid $g1.ToUpper()).TargetConfidence | Should -Be '3-High'
        }
        It 'is N/A when the target GUID is not present in the item (e.g. bundle SITs)' {
            $data = "[{`"Id`":`"$g1`",`"LowConfidenceMatch`":1,`"MediumConfidenceMatch`":0,`"HighConfidenceMatch`":0}]"
            (Get-CEConfidenceSummary -Data $data -TargetGuid $g3).TargetConfidence | Should -Be 'N/A'
        }
        It 'is N/A when no target GUID is supplied' {
            $data = "[{`"Id`":`"$g1`",`"LowConfidenceMatch`":1,`"MediumConfidenceMatch`":0,`"HighConfidenceMatch`":0}]"
            (Get-CEConfidenceSummary -Data $data).TargetConfidence | Should -Be 'N/A'
        }
    }

    Context 'degenerate input' {
        It 'returns 0-None / N/A for an empty data string' {
            $r = Get-CEConfidenceSummary -Data ''
            $r.ItemMaxConfidence | Should -Be '0-None'
            $r.TargetConfidence  | Should -Be 'N/A'
        }
        It 'returns 0-None / N/A for an empty JSON array' {
            $r = Get-CEConfidenceSummary -Data '[]' -TargetGuid $g1
            $r.ItemMaxConfidence | Should -Be '0-None'
            $r.TargetConfidence  | Should -Be 'N/A'
        }
        It 'tolerates malformed JSON without throwing' {
            $r = Get-CEConfidenceSummary -Data 'not json {' -TargetGuid $g1
            $r.ItemMaxConfidence | Should -Be '0-None'
            $r.TargetConfidence  | Should -Be 'N/A'
        }
    }
}

Describe 'Get-CESitName' {
    BeforeAll {
        $script:n1 = '11111111-1111-1111-1111-111111111111'
        $script:n2 = '22222222-2222-2222-2222-222222222222'
        $script:n3 = '33333333-3333-3333-3333-333333333333'  # deliberately absent from the map
        $script:map = @{ $n1 = 'Credit Card Number'; $n2 = 'Microsoft Entra User Credentials' }
    }

    It 'resolves GUIDs to names in order' {
        Get-CESitName -Guids "$n1,$n2" -NameMap $map |
            Should -Be 'Credit Card Number, Microsoft Entra User Credentials'
    }
    It 'falls back to the raw GUID for an unknown id (nothing silently dropped)' {
        Get-CESitName -Guids "$n1,$n3" -NameMap $map |
            Should -Be "Credit Card Number, $n3"
    }
    It 'matches the GUID case-insensitively' {
        Get-CESitName -Guids ($n1.ToUpper()) -NameMap $map | Should -Be 'Credit Card Number'
    }
    It 'trims whitespace around GUIDs' {
        Get-CESitName -Guids "  $n1 ,  $n2  " -NameMap $map |
            Should -Be 'Credit Card Number, Microsoft Entra User Credentials'
    }
    It 'returns an empty string for empty input' {
        Get-CESitName -Guids '' -NameMap $map | Should -Be ''
    }
}
