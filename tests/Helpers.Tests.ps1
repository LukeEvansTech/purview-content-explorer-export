# Run with: Invoke-Pester ./tests/Helpers.Tests.ps1
#
# Offline characterization tests for the PurviewContentExplorerHelpers module
# (helpers/src). These functions only read per-tag CSV files from a folder - no
# Purview cmdlets - so they are fully testable from synthetic fixtures on TestDrive.
#
# NOTE ON FIXTURE FILENAMES: the helpers identify label/PII tags by the CSV's
# BaseName (e.g. 'Confidential.csv', 'All Full Names.csv'). That is NOT the scheme
# Export-CEItems.ps1 writes ('items_<TagType>_<safeName>.csv'), so these fixtures
# use tag-named CSVs to exercise the real matching paths. The mismatch with the
# exporter's filenames is pinned by the 'known limitation' tests below.
BeforeAll {
    Import-Module "$PSScriptRoot/../helpers/src/PurviewContentExplorerHelpers.psd1" -Force

    # Write rows (array of hashtables) to a CSV at $dir/$name.
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
        # Label tag: Confidential -> labelled rows in EXO and SPO.
        Export-FixtureCsv -Dir $script:dir -Name 'Confidential.csv' -Rows @(
            @{ Location = 'exo-a'; Workload = 'EXO' },
            @{ Location = 'spo-b'; Workload = 'SPO' }
        )
        # Non-label tag: a SIT export -> counted in Total but never Labelled.
        Export-FixtureCsv -Dir $script:dir -Name 'Credit Card Number.csv' -Rows @(
            @{ Location = 'exo-c'; Workload = 'EXO' },
            @{ Location = 'exo-d'; Workload = 'EXO' }
        )
        $script:result = Get-LabelCoverageByWorkload -Path $script:dir
    }

    It 'returns one row per distinct workload, sorted' {
        @($script:result).Count | Should -Be 2
        $script:result.Workload | Should -Be @('EXO', 'SPO')
    }
    It 'counts every CSV row in Total regardless of tag' {
        ($script:result | Where-Object Workload -eq 'EXO').TotalItems | Should -Be 3
    }
    It 'counts only label-tag rows as Labelled' {
        ($script:result | Where-Object Workload -eq 'EXO').Labelled | Should -Be 1
    }
    It 'derives Unlabelled as Total minus Labelled' {
        ($script:result | Where-Object Workload -eq 'EXO').Unlabelled | Should -Be 2
    }
    It 'computes coverage percentage rounded to one decimal place' {
        ($script:result | Where-Object Workload -eq 'EXO').CoveragePct | Should -Be 33.3
        ($script:result | Where-Object Workload -eq 'SPO').CoveragePct | Should -Be 100.0
    }

    Context 'known limitation: exporter filename scheme is not recognised' {
        It 'does not treat an items_<TagType>_<name>.csv label export as a label tag' {
            $d = Join-Path $TestDrive 'coverage-itemsprefix'
            Export-FixtureCsv -Dir $d -Name 'items_Sensitivity_Confidential.csv' -Rows @(
                @{ Location = 'exo-a'; Workload = 'EXO' }
            )
            # The anchored '^(public|internal|confidential|...)' pattern can't match a
            # name starting with 'items_', so the row counts toward Total but not Labelled.
            $r = Get-LabelCoverageByWorkload -Path $d
            $r.TotalItems | Should -Be 1
            $r.Labelled   | Should -Be 0
        }
    }
}

Describe 'Find-UnlabeledPII' {
    It 'returns PII items whose Location is not present under any label tag' {
        $d = Join-Path $TestDrive 'pii-basic'
        Export-FixtureCsv -Dir $d -Name 'TestPII.csv' -Rows @(
            @{ Location = 'item-a'; Workload = 'EXO'; ItemSize = 10; Modified = '2026-01-01' },
            @{ Location = 'item-b'; Workload = 'SPO'; ItemSize = 20; Modified = '2026-02-02' }
        )
        Export-FixtureCsv -Dir $d -Name 'Confidential.csv' -Rows @(
            @{ Location = 'item-a' }  # item-a is labelled, item-b is not
        )
        $out = Find-UnlabeledPII -Path $d -PIIClassifier 'TestPII'
        @($out).Count | Should -Be 1
        $out.Location | Should -Be 'item-b'
    }

    It 'projects Classifier/Location/Workload/ItemSize/Modified onto the output' {
        $d = Join-Path $TestDrive 'pii-shape'
        Export-FixtureCsv -Dir $d -Name 'TestPII.csv' -Rows @(
            @{ Location = 'item-x'; Workload = 'Teams'; ItemSize = 99; Modified = '2026-03-03' }
        )
        $out = Find-UnlabeledPII -Path $d -PIIClassifier 'TestPII'
        $out.Classifier | Should -Be 'TestPII'
        $out.Location   | Should -Be 'item-x'
        $out.Workload   | Should -Be 'Teams'
        $out.ItemSize   | Should -Be '99'
        $out.Modified   | Should -Be '2026-03-03'
    }

    It 'returns nothing when every PII item is labelled' {
        $d = Join-Path $TestDrive 'pii-all-labelled'
        Export-FixtureCsv -Dir $d -Name 'TestPII.csv' -Rows @(
            @{ Location = 'item-a'; Workload = 'EXO'; ItemSize = 1; Modified = '2026-01-01' }
        )
        Export-FixtureCsv -Dir $d -Name 'Internal.csv' -Rows @(
            @{ Location = 'item-a' }
        )
        Find-UnlabeledPII -Path $d -PIIClassifier 'TestPII' | Should -BeNullOrEmpty
    }

    It 'warns and returns nothing when no CSV matches the PII pattern' {
        $d = Join-Path $TestDrive 'pii-nomatch'
        Export-FixtureCsv -Dir $d -Name 'Confidential.csv' -Rows @(
            @{ Location = 'item-a'; Workload = 'EXO' }
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
        # OLD: item-a under {SIT, Confidential}, item-b under {SIT}
        Export-FixtureCsv -Dir $script:old -Name 'SIT.csv' -Rows @(
            @{ Location = 'item-a' }, @{ Location = 'item-b' }
        )
        Export-FixtureCsv -Dir $script:old -Name 'Confidential.csv' -Rows @(
            @{ Location = 'item-a' }
        )
        # NEW: item-a under {SIT} (label dropped), item-c under {SIT} (new)
        Export-FixtureCsv -Dir $script:new -Name 'SIT.csv' -Rows @(
            @{ Location = 'item-a' }, @{ Location = 'item-c' }
        )
        $script:delta = Compare-ExportDelta -Old $script:old -New $script:new
    }

    It 'flags an item present only in the new export as Added' {
        $added = $script:delta | Where-Object Location -eq 'item-c'
        $added.Change  | Should -Be 'Added'
        $added.OldTags | Should -BeNullOrEmpty
        $added.NewTags | Should -Be 'SIT'
    }
    It 'flags an item present only in the old export as Removed' {
        $removed = $script:delta | Where-Object Location -eq 'item-b'
        $removed.Change  | Should -Be 'Removed'
        $removed.OldTags | Should -Be 'SIT'
        $removed.NewTags | Should -BeNullOrEmpty
    }
    It 'flags an item whose tag set changed as Reclassified' {
        $recl = $script:delta | Where-Object Location -eq 'item-a'
        $recl.Change | Should -Be 'Reclassified'
        ($recl.OldTags -split ',' | Sort-Object) | Should -Be @('Confidential', 'SIT')
        $recl.NewTags | Should -Be 'SIT'
    }
    It 'emits exactly the three changed items (unchanged items are omitted)' {
        @($script:delta).Count | Should -Be 3
    }
    It 'returns nothing when the two exports are identical' {
        $same = Join-Path $TestDrive 'delta-same'
        Export-FixtureCsv -Dir $same -Name 'SIT.csv' -Rows @(
            @{ Location = 'item-a' }
        )
        Compare-ExportDelta -Old $same -New $same | Should -BeNullOrEmpty
    }
}
