# Run with: Invoke-Pester ./tests/Helpers.Tests.ps1
#
# Offline characterization tests for the PurviewContentExplorerHelpers module
# (helpers/src). These functions only read per-tag CSV files from a folder - no
# Purview cmdlets - so they are fully testable from synthetic fixtures on TestDrive.
#
# The helpers read the TagType / TagName / Workload / Location columns that
# Export-CEItems.ps1 writes into every row, so they are independent of how the
# CSV files are named. Fixtures therefore use the exporter's real
# 'items_<TagType>_<safeName>.csv' filenames to prove that independence.
BeforeAll {
    Import-Module "$PSScriptRoot/../helpers/src/PurviewContentExplorerHelpers.psd1" -Force

    # Write rows (array of hashtables with identical keys) to a CSV at $dir/$name.
    function Export-FixtureCsv {
        param([string]$Dir, [string]$Name, [object[]]$Rows)
        $null = New-Item -ItemType Directory -Path $Dir -Force
        $Rows | ForEach-Object { [pscustomobject]$_ } |
            Export-Csv -Path (Join-Path $Dir $Name) -NoTypeInformation
    }
}

Describe 'Get-LabelCoverageByWorkload' {
    BeforeAll {
        $script:dir = Join-Path $TestDrive 'coverage'
        # Sensitivity label export -> exo-a (EXO) and spo-b (SPO) are labelled.
        Export-FixtureCsv -Dir $script:dir -Name 'items_Sensitivity_Confidential.csv' -Rows @(
            @{ TagType = 'Sensitivity'; TagName = 'Confidential'; Workload = 'EXO'; Location = 'exo-a' },
            @{ TagType = 'Sensitivity'; TagName = 'Confidential'; Workload = 'SPO'; Location = 'spo-b' }
        )
        # SIT export -> exo-c, exo-d, and exo-a again (exo-a also matches a SIT).
        Export-FixtureCsv -Dir $script:dir -Name 'items_SensitiveInformationType_Credit Card Number.csv' -Rows @(
            @{ TagType = 'SensitiveInformationType'; TagName = 'Credit Card Number'; Workload = 'EXO'; Location = 'exo-c' },
            @{ TagType = 'SensitiveInformationType'; TagName = 'Credit Card Number'; Workload = 'EXO'; Location = 'exo-d' },
            @{ TagType = 'SensitiveInformationType'; TagName = 'Credit Card Number'; Workload = 'EXO'; Location = 'exo-a' }
        )
        $script:result = Get-LabelCoverageByWorkload -Path $script:dir
    }

    It 'returns one row per distinct workload, sorted' {
        @($script:result).Count | Should -Be 2
        $script:result.Workload | Should -Be @('EXO', 'SPO')
    }
    It 'de-duplicates items by Location across tags (exo-a counted once)' {
        ($script:result | Where-Object Workload -eq 'EXO').TotalItems | Should -Be 3
    }
    It 'counts an item as labelled when it appears under a Sensitivity tag' {
        ($script:result | Where-Object Workload -eq 'EXO').Labelled | Should -Be 1
    }
    It 'derives Unlabelled as Total minus Labelled' {
        ($script:result | Where-Object Workload -eq 'EXO').Unlabelled | Should -Be 2
    }
    It 'computes coverage percentage rounded to one decimal place' {
        ($script:result | Where-Object Workload -eq 'EXO').CoveragePct | Should -Be 33.3
        ($script:result | Where-Object Workload -eq 'SPO').CoveragePct | Should -Be 100.0
    }
    It 'recognises a Sensitivity export regardless of filename (items_*.csv)' {
        # The label CSV is named items_Sensitivity_Confidential.csv; if the helper still keyed
        # off the filename it would find zero labelled items. It does not.
        ($script:result | Where-Object Workload -eq 'SPO').Labelled | Should -Be 1
    }
}

Describe 'Find-UnlabeledPII' {
    It 'returns PII items whose Location never appears under a Sensitivity tag' {
        $d = Join-Path $TestDrive 'pii-basic'
        Export-FixtureCsv -Dir $d -Name 'items_SensitiveInformationType_TestPII.csv' -Rows @(
            @{ TagType = 'SensitiveInformationType'; TagName = 'TestPII'; Workload = 'EXO'; Location = 'item-a'; ItemSize = 10; Modified = '2026-01-01' },
            @{ TagType = 'SensitiveInformationType'; TagName = 'TestPII'; Workload = 'SPO'; Location = 'item-b'; ItemSize = 20; Modified = '2026-02-02' }
        )
        Export-FixtureCsv -Dir $d -Name 'items_Sensitivity_Confidential.csv' -Rows @(
            @{ TagType = 'Sensitivity'; TagName = 'Confidential'; Workload = 'EXO'; Location = 'item-a'; ItemSize = 10; Modified = '2026-01-01' }
        )
        $out = Find-UnlabeledPII -Path $d -PIIClassifier 'TestPII'
        @($out).Count | Should -Be 1
        $out.Location | Should -Be 'item-b'
    }

    It 'projects Classifier/Location/Workload/ItemSize/Modified onto the output' {
        $d = Join-Path $TestDrive 'pii-shape'
        Export-FixtureCsv -Dir $d -Name 'items_SensitiveInformationType_TestPII.csv' -Rows @(
            @{ TagType = 'SensitiveInformationType'; TagName = 'TestPII'; Workload = 'Teams'; Location = 'item-x'; ItemSize = 99; Modified = '2026-03-03' }
        )
        $out = Find-UnlabeledPII -Path $d -PIIClassifier 'TestPII'
        $out.Classifier | Should -Be 'TestPII'
        $out.Location   | Should -Be 'item-x'
        $out.Workload   | Should -Be 'Teams'
        $out.ItemSize   | Should -Be '99'
        $out.Modified   | Should -Be '2026-03-03'
    }

    It 'emits one row per item, joining multiple matching classifiers' {
        $d = Join-Path $TestDrive 'pii-multi'
        Export-FixtureCsv -Dir $d -Name 'items_SensitiveInformationType_All Full Names.csv' -Rows @(
            @{ TagType = 'SensitiveInformationType'; TagName = 'All Full Names'; Workload = 'EXO'; Location = 'item-x'; ItemSize = 5; Modified = '2026-01-01' }
        )
        Export-FixtureCsv -Dir $d -Name 'items_SensitiveInformationType_TestPII.csv' -Rows @(
            @{ TagType = 'SensitiveInformationType'; TagName = 'TestPII'; Workload = 'EXO'; Location = 'item-x'; ItemSize = 5; Modified = '2026-01-01' }
        )
        $out = Find-UnlabeledPII -Path $d -PIIClassifier 'All Full Names', 'TestPII'
        @($out).Count   | Should -Be 1
        $out.Classifier | Should -Be 'All Full Names, TestPII'
    }

    It 'returns nothing when every PII item is labelled' {
        $d = Join-Path $TestDrive 'pii-all-labelled'
        Export-FixtureCsv -Dir $d -Name 'items_SensitiveInformationType_TestPII.csv' -Rows @(
            @{ TagType = 'SensitiveInformationType'; TagName = 'TestPII'; Workload = 'EXO'; Location = 'item-a'; ItemSize = 1; Modified = '2026-01-01' }
        )
        Export-FixtureCsv -Dir $d -Name 'items_Sensitivity_Internal.csv' -Rows @(
            @{ TagType = 'Sensitivity'; TagName = 'Internal'; Workload = 'EXO'; Location = 'item-a'; ItemSize = 1; Modified = '2026-01-01' }
        )
        Find-UnlabeledPII -Path $d -PIIClassifier 'TestPII' | Should -BeNullOrEmpty
    }

    It 'warns and returns nothing when no row matches the PII classifier' {
        $d = Join-Path $TestDrive 'pii-nomatch'
        Export-FixtureCsv -Dir $d -Name 'items_Sensitivity_Confidential.csv' -Rows @(
            @{ TagType = 'Sensitivity'; TagName = 'Confidential'; Workload = 'EXO'; Location = 'item-a' }
        )
        Find-UnlabeledPII -Path $d -PIIClassifier 'TestPII' -WarningAction SilentlyContinue |
            Should -BeNullOrEmpty
    }

    It 'returns nothing when the folder has no CSV files' {
        $d = Join-Path $TestDrive 'pii-empty'
        $null = New-Item -ItemType Directory -Path $d -Force
        Find-UnlabeledPII -Path $d -WarningAction SilentlyContinue | Should -BeNullOrEmpty
    }
}

Describe 'Compare-ExportDelta' {
    BeforeAll {
        $script:old = Join-Path $TestDrive 'delta-old'
        $script:new = Join-Path $TestDrive 'delta-new'
        # OLD: item-a under {SIT/Credit Card Number, Sensitivity/Confidential}, item-b under {SIT/...}
        Export-FixtureCsv -Dir $script:old -Name 'items_SensitiveInformationType_Credit Card Number.csv' -Rows @(
            @{ TagType = 'SensitiveInformationType'; TagName = 'Credit Card Number'; Workload = 'EXO'; Location = 'item-a' },
            @{ TagType = 'SensitiveInformationType'; TagName = 'Credit Card Number'; Workload = 'EXO'; Location = 'item-b' }
        )
        Export-FixtureCsv -Dir $script:old -Name 'items_Sensitivity_Confidential.csv' -Rows @(
            @{ TagType = 'Sensitivity'; TagName = 'Confidential'; Workload = 'EXO'; Location = 'item-a' }
        )
        # NEW: item-a keeps only the SIT (label dropped), item-c is new under the SIT.
        Export-FixtureCsv -Dir $script:new -Name 'items_SensitiveInformationType_Credit Card Number.csv' -Rows @(
            @{ TagType = 'SensitiveInformationType'; TagName = 'Credit Card Number'; Workload = 'EXO'; Location = 'item-a' },
            @{ TagType = 'SensitiveInformationType'; TagName = 'Credit Card Number'; Workload = 'EXO'; Location = 'item-c' }
        )
        $script:delta = Compare-ExportDelta -Old $script:old -New $script:new
    }

    It 'flags an item present only in the new export as Added' {
        $added = $script:delta | Where-Object Location -eq 'item-c'
        $added.Change  | Should -Be 'Added'
        $added.OldTags | Should -BeNullOrEmpty
        $added.NewTags | Should -Be 'SensitiveInformationType/Credit Card Number'
    }
    It 'flags an item present only in the old export as Removed' {
        $removed = $script:delta | Where-Object Location -eq 'item-b'
        $removed.Change  | Should -Be 'Removed'
        $removed.OldTags | Should -Be 'SensitiveInformationType/Credit Card Number'
        $removed.NewTags | Should -BeNullOrEmpty
    }
    It 'flags an item whose tag set changed as Reclassified, using TagType/TagName' {
        $recl = $script:delta | Where-Object Location -eq 'item-a'
        $recl.Change | Should -Be 'Reclassified'
        ($recl.OldTags -split ', ' | Sort-Object) |
            Should -Be @('SensitiveInformationType/Credit Card Number', 'Sensitivity/Confidential')
        $recl.NewTags | Should -Be 'SensitiveInformationType/Credit Card Number'
    }
    It 'emits exactly the three changed items (unchanged items are omitted)' {
        @($script:delta).Count | Should -Be 3
    }
    It 'returns nothing when the two exports are identical' {
        $same = Join-Path $TestDrive 'delta-same'
        Export-FixtureCsv -Dir $same -Name 'items_SensitiveInformationType_Credit Card Number.csv' -Rows @(
            @{ TagType = 'SensitiveInformationType'; TagName = 'Credit Card Number'; Workload = 'EXO'; Location = 'item-a' }
        )
        Compare-ExportDelta -Old $same -New $same | Should -BeNullOrEmpty
    }
    It 'keys tags off TagType/TagName, not the filename (a renamed file is not a change)' {
        $o = Join-Path $TestDrive 'delta-rename-old'
        $n = Join-Path $TestDrive 'delta-rename-new'
        Export-FixtureCsv -Dir $o -Name 'items_Sensitivity_Confidential.csv' -Rows @(
            @{ TagType = 'Sensitivity'; TagName = 'Confidential'; Workload = 'EXO'; Location = 'item-z' }
        )
        # Same row content, different filename.
        Export-FixtureCsv -Dir $n -Name 'renamed-export.csv' -Rows @(
            @{ TagType = 'Sensitivity'; TagName = 'Confidential'; Workload = 'EXO'; Location = 'item-z' }
        )
        Compare-ExportDelta -Old $o -New $n | Should -BeNullOrEmpty
    }
}
