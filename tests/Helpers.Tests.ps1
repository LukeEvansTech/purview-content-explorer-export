# Run with: Invoke-Pester ./tests/Helpers.Tests.ps1
#
# Offline characterization tests for the PurviewContentExplorerHelpers module
# (helpers/src). These functions only read per-tag CSV files from a folder - no
# Purview cmdlets - so they are fully testable from synthetic fixtures on TestDrive.
#
# Fixtures mirror the exporter's REAL output schema (docs/docs/output-schema.md,
# examples/items_all.sample.csv): every row carries Location == Workload (the cmdlet
# emits both, duplicated), and item identity comes from FileUrl (SPO/ODB) or
# FileSourceUrl+FileName (EXO/Teams). Get-FixtureRow bakes Location = Workload into
# every fixture row so the suite pins the schema the producer actually emits.
BeforeAll {
    Import-Module "$PSScriptRoot/../helpers/src/PurviewContentExplorerHelpers.psd1" -Force

    # One exporter-schema row as a hashtable. Location is deliberately NOT a parameter:
    # in real output it always duplicates Workload and must never be an item identity.
    function Get-FixtureRow {
        param(
            [string]$TagType, [string]$TagName, [string]$Workload,
            [string]$FileUrl = '', [string]$FileSourceUrl = '', [string]$FileName = '',
            [string]$SensitivityLabel = '',
            [string]$LastModifiedTime = '2026-01-01T00:00:00Z'
        )
        @{
            TagType = $TagType; TagName = $TagName; Workload = $Workload; Location = $Workload
            FileSourceUrl = $FileSourceUrl; FileUrl = $FileUrl; FileName = $FileName
            SensitivityLabel = $SensitivityLabel
            LastModifiedTime = $LastModifiedTime
        }
    }

    # Write rows (array of hashtables with identical keys) to a CSV at $dir/$name.
    function Export-FixtureCsv {
        param([string]$Dir, [string]$Name, [object[]]$Rows)
        $null = New-Item -ItemType Directory -Path $Dir -Force
        $Rows | ForEach-Object { [pscustomobject]$_ } |
            Export-Csv -Path (Join-Path $Dir $Name) -NoTypeInformation
    }

    # Shorthands for common fixture rows.
    function Get-SpoRow {
        param([string]$TagType, [string]$TagName, [string]$Doc, [string]$Workload = 'SPO')
        Get-FixtureRow -TagType $TagType -TagName $TagName -Workload $Workload `
            -FileSourceUrl 'https://contoso.sharepoint.com/sites/finance' `
            -FileUrl "https://contoso.sharepoint.com/sites/finance/Shared Documents/$Doc" `
            -FileName $Doc
    }
    function Get-ExoRow {
        param([string]$TagType, [string]$TagName, [string]$Upn, [string]$Subject)
        # EXO rows have no FileUrl - identity falls back to FileSourceUrl|FileName.
        Get-FixtureRow -TagType $TagType -TagName $TagName -Workload 'EXO' `
            -FileSourceUrl $Upn -FileUrl '' -FileName $Subject
    }
}

Describe 'Get-LabelCoverageByWorkload' {
    BeforeAll {
        $script:dir = Join-Path $TestDrive 'coverage'
        # Sensitivity sweep: doc-a.docx (SPO) and one EXO mail are labelled.
        Export-FixtureCsv -Dir $script:dir -Name 'items_Sensitivity_Confidential.csv' -Rows @(
            (Get-SpoRow -TagType 'Sensitivity' -TagName 'Confidential' -Doc 'doc-a.docx'),
            (Get-ExoRow -TagType 'Sensitivity' -TagName 'Confidential' -Upn 'alex@contoso.com' -Subject 'Q3 numbers')
        )
        # SIT sweep: three distinct SPO docs (incl. doc-a again) + two distinct EXO mails (incl. the labelled one).
        Export-FixtureCsv -Dir $script:dir -Name 'items_SensitiveInformationType_Credit Card Number.csv' -Rows @(
            (Get-SpoRow -TagType 'SensitiveInformationType' -TagName 'Credit Card Number' -Doc 'doc-a.docx'),
            (Get-SpoRow -TagType 'SensitiveInformationType' -TagName 'Credit Card Number' -Doc 'doc-b.xlsx'),
            (Get-SpoRow -TagType 'SensitiveInformationType' -TagName 'Credit Card Number' -Doc 'doc-c.pdf'),
            (Get-ExoRow -TagType 'SensitiveInformationType' -TagName 'Credit Card Number' -Upn 'alex@contoso.com' -Subject 'Q3 numbers'),
            (Get-ExoRow -TagType 'SensitiveInformationType' -TagName 'Credit Card Number' -Upn 'jamie@contoso.com' -Subject 'receipts')
        )
        $script:result = Get-LabelCoverageByWorkload -Path $script:dir
    }

    It 'returns one row per distinct workload, sorted' {
        @($script:result).Count | Should -Be 2
        $script:result.Workload | Should -Be @('EXO', 'SPO')
    }
    It 'counts items distinctly even though every row has Location == Workload (regression: Location is not an identity)' {
        # The old Location-keyed code collapsed each workload to TotalItems = 1.
        ($script:result | Where-Object Workload -eq 'SPO').TotalItems | Should -Be 3
        ($script:result | Where-Object Workload -eq 'EXO').TotalItems | Should -Be 2
    }
    It 'de-duplicates an item that appears under several tags' {
        # doc-a.docx is in both the Sensitivity and SIT sweeps - counted once.
        ($script:result | Where-Object Workload -eq 'SPO').TotalItems | Should -Be 3
    }
    It 'counts an item as labelled only via a Sensitivity row' {
        ($script:result | Where-Object Workload -eq 'SPO').Labelled | Should -Be 1
        ($script:result | Where-Object Workload -eq 'EXO').Labelled | Should -Be 1
    }
    It 'derives Unlabelled as Total minus Labelled' {
        ($script:result | Where-Object Workload -eq 'SPO').Unlabelled | Should -Be 2
    }
    It 'computes coverage percentage rounded to one decimal place' {
        ($script:result | Where-Object Workload -eq 'SPO').CoveragePct | Should -Be 33.3
        ($script:result | Where-Object Workload -eq 'EXO').CoveragePct | Should -Be 50.0
    }

    Context 'items_all.csv roll-up handling' {
        It 'skips items_all.csv when per-tag CSVs exist (no double parse, no phantom items)' {
            $d = Join-Path $TestDrive 'coverage-rollup'
            Export-FixtureCsv -Dir $d -Name 'items_Sensitivity_Confidential.csv' -Rows @(
                (Get-SpoRow -TagType 'Sensitivity' -TagName 'Confidential' -Doc 'doc-a.docx')
            )
            # Roll-up contains the same row PLUS an item that exists nowhere else - if the
            # roll-up were read, TotalItems would be 2.
            Export-FixtureCsv -Dir $d -Name 'items_all.csv' -Rows @(
                (Get-SpoRow -TagType 'Sensitivity' -TagName 'Confidential' -Doc 'doc-a.docx'),
                (Get-SpoRow -TagType 'Sensitivity' -TagName 'Confidential' -Doc 'rollup-only.docx')
            )
            (Get-LabelCoverageByWorkload -Path $d).TotalItems | Should -Be 1
        }
        It 'falls back to items_all.csv when it is the only CSV in the folder' {
            $d = Join-Path $TestDrive 'coverage-rollup-only'
            Export-FixtureCsv -Dir $d -Name 'items_all.csv' -Rows @(
                (Get-SpoRow -TagType 'Sensitivity' -TagName 'Confidential' -Doc 'doc-a.docx'),
                (Get-SpoRow -TagType 'SensitiveInformationType' -TagName 'Credit Card Number' -Doc 'doc-b.xlsx')
            )
            $r = Get-LabelCoverageByWorkload -Path $d
            $r.TotalItems | Should -Be 2
            $r.Labelled   | Should -Be 1
        }
    }

    It 'counts an item as labelled via its per-row SensitivityLabel GUID, without a Sensitivity sweep' {
        # The exporter writes the applied label GUID on every row regardless of swept tag type,
        # so coverage works from a SIT-only export folder.
        $d = Join-Path $TestDrive 'coverage-senslabel'
        Export-FixtureCsv -Dir $d -Name 'items_SensitiveInformationType_Credit Card Number.csv' -Rows @(
            (Get-FixtureRow -TagType 'SensitiveInformationType' -TagName 'Credit Card Number' -Workload 'ODB' `
                -FileUrl 'https://contoso-my.sharepoint.com/personal/a/deploy.ps1' -FileName 'deploy.ps1' `
                -SensitivityLabel '594ebd0a-75d8-486c-ab01-b42307a7a7e7'),
            (Get-FixtureRow -TagType 'SensitiveInformationType' -TagName 'Credit Card Number' -Workload 'ODB' `
                -FileUrl 'https://contoso-my.sharepoint.com/personal/a/notes.txt' -FileName 'notes.txt')
        )
        $r = Get-LabelCoverageByWorkload -Path $d
        $r.TotalItems | Should -Be 2
        $r.Labelled   | Should -Be 1
    }

    It 'ignores CSVs that lack the exporter columns' {
        $d = Join-Path $TestDrive 'coverage-foreign'
        Export-FixtureCsv -Dir $d -Name 'foreign.csv' -Rows @(
            @{ Name = 'not-an-export'; Value = 42 }
        )
        Get-LabelCoverageByWorkload -Path $d | Should -BeNullOrEmpty
    }
}

Describe 'Find-UnlabeledPII' {
    It 'returns PII items that never appear under a Sensitivity tag' {
        $d = Join-Path $TestDrive 'pii-basic'
        Export-FixtureCsv -Dir $d -Name 'items_SensitiveInformationType_TestPII.csv' -Rows @(
            (Get-SpoRow -TagType 'SensitiveInformationType' -TagName 'TestPII' -Doc 'doc-a.docx'),
            (Get-SpoRow -TagType 'SensitiveInformationType' -TagName 'TestPII' -Doc 'doc-b.xlsx')
        )
        Export-FixtureCsv -Dir $d -Name 'items_Sensitivity_Confidential.csv' -Rows @(
            (Get-SpoRow -TagType 'Sensitivity' -TagName 'Confidential' -Doc 'doc-a.docx')
        )
        $out = @(Find-UnlabeledPII -Path $d -PIIClassifier 'TestPII')
        $out.Count | Should -Be 1
        $out[0].FileName | Should -Be 'doc-b.xlsx'
    }

    It 'does not suppress a whole workload when one item in it is labelled (regression: Location is not an identity)' {
        # Every row here has Location='EXO'; the old Location-keyed code put 'EXO' in the
        # labelled set and suppressed ALL EXO PII as soon as any EXO item was labelled.
        $d = Join-Path $TestDrive 'pii-regression'
        Export-FixtureCsv -Dir $d -Name 'items_SensitiveInformationType_TestPII.csv' -Rows @(
            (Get-ExoRow -TagType 'SensitiveInformationType' -TagName 'TestPII' -Upn 'alex@contoso.com' -Subject 'labelled mail'),
            (Get-ExoRow -TagType 'SensitiveInformationType' -TagName 'TestPII' -Upn 'jamie@contoso.com' -Subject 'unlabelled mail')
        )
        Export-FixtureCsv -Dir $d -Name 'items_Sensitivity_Confidential.csv' -Rows @(
            (Get-ExoRow -TagType 'Sensitivity' -TagName 'Confidential' -Upn 'alex@contoso.com' -Subject 'labelled mail')
        )
        $out = @(Find-UnlabeledPII -Path $d -PIIClassifier 'TestPII')
        $out.Count | Should -Be 1
        $out[0].FileSourceUrl | Should -Be 'jamie@contoso.com'
    }

    It 'projects Classifier/Workload/FileName/FileUrl/FileSourceUrl/LastModifiedTime onto the output' {
        $d = Join-Path $TestDrive 'pii-shape'
        Export-FixtureCsv -Dir $d -Name 'items_SensitiveInformationType_TestPII.csv' -Rows @(
            (Get-FixtureRow -TagType 'SensitiveInformationType' -TagName 'TestPII' -Workload 'SPO' `
                -FileSourceUrl 'https://contoso.sharepoint.com/sites/hr' `
                -FileUrl 'https://contoso.sharepoint.com/sites/hr/cv.pdf' -FileName 'cv.pdf' `
                -LastModifiedTime '2026-03-03T08:00:00Z')
        )
        $out = Find-UnlabeledPII -Path $d -PIIClassifier 'TestPII'
        $out.Classifier       | Should -Be 'TestPII'
        $out.Workload         | Should -Be 'SPO'
        $out.FileName         | Should -Be 'cv.pdf'
        $out.FileUrl          | Should -Be 'https://contoso.sharepoint.com/sites/hr/cv.pdf'
        $out.FileSourceUrl    | Should -Be 'https://contoso.sharepoint.com/sites/hr'
        $out.LastModifiedTime | Should -Be '2026-03-03T08:00:00Z'
    }

    It 'matches labels case-insensitively on the item identity' {
        $d = Join-Path $TestDrive 'pii-case'
        Export-FixtureCsv -Dir $d -Name 'items_SensitiveInformationType_TestPII.csv' -Rows @(
            (Get-FixtureRow -TagType 'SensitiveInformationType' -TagName 'TestPII' -Workload 'SPO' `
                -FileUrl 'https://contoso.sharepoint.com/Sites/HR/cv.pdf' -FileName 'cv.pdf')
        )
        # Label sweep recorded the same item with different URL casing.
        Export-FixtureCsv -Dir $d -Name 'items_Sensitivity_Confidential.csv' -Rows @(
            (Get-FixtureRow -TagType 'Sensitivity' -TagName 'Confidential' -Workload 'SPO' `
                -FileUrl 'https://contoso.sharepoint.com/sites/hr/cv.pdf' -FileName 'cv.pdf')
        )
        Find-UnlabeledPII -Path $d -PIIClassifier 'TestPII' -WarningAction SilentlyContinue |
            Should -BeNullOrEmpty
    }

    It 'emits one row per item, joining multiple matching classifiers' {
        $d = Join-Path $TestDrive 'pii-multi'
        Export-FixtureCsv -Dir $d -Name 'items_SensitiveInformationType_All Full Names.csv' -Rows @(
            (Get-SpoRow -TagType 'SensitiveInformationType' -TagName 'All Full Names' -Doc 'doc-x.docx')
        )
        Export-FixtureCsv -Dir $d -Name 'items_SensitiveInformationType_TestPII.csv' -Rows @(
            (Get-SpoRow -TagType 'SensitiveInformationType' -TagName 'TestPII' -Doc 'doc-x.docx')
        )
        $out = @(Find-UnlabeledPII -Path $d -PIIClassifier 'All Full Names', 'TestPII')
        $out.Count        | Should -Be 1
        $out[0].Classifier | Should -Be 'All Full Names, TestPII'
    }

    It 'excludes an item whose own row carries a SensitivityLabel GUID, without a Sensitivity sweep' {
        $d = Join-Path $TestDrive 'pii-senslabel'
        Export-FixtureCsv -Dir $d -Name 'items_SensitiveInformationType_TestPII.csv' -Rows @(
            (Get-FixtureRow -TagType 'SensitiveInformationType' -TagName 'TestPII' -Workload 'SPO' `
                -FileUrl 'https://contoso.sharepoint.com/sites/x/labelled.docx' -FileName 'labelled.docx' `
                -SensitivityLabel '594ebd0a-75d8-486c-ab01-b42307a7a7e7'),
            (Get-FixtureRow -TagType 'SensitiveInformationType' -TagName 'TestPII' -Workload 'SPO' `
                -FileUrl 'https://contoso.sharepoint.com/sites/x/bare.docx' -FileName 'bare.docx')
        )
        $out = @(Find-UnlabeledPII -Path $d -PIIClassifier 'TestPII')
        $out.Count       | Should -Be 1
        $out[0].FileName | Should -Be 'bare.docx'
    }

    It 'returns nothing when every PII item is labelled' {
        $d = Join-Path $TestDrive 'pii-all-labelled'
        Export-FixtureCsv -Dir $d -Name 'items_SensitiveInformationType_TestPII.csv' -Rows @(
            (Get-SpoRow -TagType 'SensitiveInformationType' -TagName 'TestPII' -Doc 'doc-a.docx')
        )
        Export-FixtureCsv -Dir $d -Name 'items_Sensitivity_Internal.csv' -Rows @(
            (Get-SpoRow -TagType 'Sensitivity' -TagName 'Internal' -Doc 'doc-a.docx')
        )
        Find-UnlabeledPII -Path $d -PIIClassifier 'TestPII' | Should -BeNullOrEmpty
    }

    It 'warns and returns nothing when no row matches the PII pattern' {
        $d = Join-Path $TestDrive 'pii-nomatch'
        Export-FixtureCsv -Dir $d -Name 'items_Sensitivity_Confidential.csv' -Rows @(
            (Get-SpoRow -TagType 'Sensitivity' -TagName 'Confidential' -Doc 'doc-a.docx')
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
        # OLD: doc-a under {SIT, Sensitivity}, doc-b under {SIT}.
        Export-FixtureCsv -Dir $script:old -Name 'items_SensitiveInformationType_Credit Card Number.csv' -Rows @(
            (Get-SpoRow -TagType 'SensitiveInformationType' -TagName 'Credit Card Number' -Doc 'doc-a.docx'),
            (Get-SpoRow -TagType 'SensitiveInformationType' -TagName 'Credit Card Number' -Doc 'doc-b.xlsx')
        )
        Export-FixtureCsv -Dir $script:old -Name 'items_Sensitivity_Confidential.csv' -Rows @(
            (Get-SpoRow -TagType 'Sensitivity' -TagName 'Confidential' -Doc 'doc-a.docx')
        )
        # NEW: doc-a keeps only the SIT (label dropped), doc-c is new under the SIT.
        Export-FixtureCsv -Dir $script:new -Name 'items_SensitiveInformationType_Credit Card Number.csv' -Rows @(
            (Get-SpoRow -TagType 'SensitiveInformationType' -TagName 'Credit Card Number' -Doc 'doc-a.docx'),
            (Get-SpoRow -TagType 'SensitiveInformationType' -TagName 'Credit Card Number' -Doc 'doc-c.pdf')
        )
        $script:delta = @(Compare-ExportDelta -Old $script:old -New $script:new)
    }

    It 'flags an item present only in the new export as Added' {
        $added = $script:delta | Where-Object Item -like '*doc-c.pdf'
        $added.Change  | Should -Be 'Added'
        $added.OldTags | Should -BeNullOrEmpty
        $added.NewTags | Should -Be 'SensitiveInformationType/Credit Card Number'
    }
    It 'flags an item present only in the old export as Removed' {
        $removed = $script:delta | Where-Object Item -like '*doc-b.xlsx'
        $removed.Change  | Should -Be 'Removed'
        $removed.OldTags | Should -Be 'SensitiveInformationType/Credit Card Number'
        $removed.NewTags | Should -BeNullOrEmpty
    }
    It 'flags an item whose tag set changed as Reclassified, using TagType/TagName' {
        $recl = $script:delta | Where-Object Item -like '*doc-a.docx'
        $recl.Change | Should -Be 'Reclassified'
        ($recl.OldTags -split ', ' | Sort-Object) |
            Should -Be @('SensitiveInformationType/Credit Card Number', 'Sensitivity/Confidential')
        $recl.NewTags | Should -Be 'SensitiveInformationType/Credit Card Number'
    }
    It 'emits exactly the three changed items (unchanged items are omitted)' {
        $script:delta.Count | Should -Be 3
    }
    It 'returns nothing when the two exports are identical' {
        $same = Join-Path $TestDrive 'delta-same'
        Export-FixtureCsv -Dir $same -Name 'items_SensitiveInformationType_Credit Card Number.csv' -Rows @(
            (Get-SpoRow -TagType 'SensitiveInformationType' -TagName 'Credit Card Number' -Doc 'doc-a.docx')
        )
        Compare-ExportDelta -Old $same -New $same | Should -BeNullOrEmpty
    }
    It 'keys items off row columns, not the filename (a renamed file is not a change)' {
        $o = Join-Path $TestDrive 'delta-rename-old'
        $n = Join-Path $TestDrive 'delta-rename-new'
        Export-FixtureCsv -Dir $o -Name 'items_Sensitivity_Confidential.csv' -Rows @(
            (Get-SpoRow -TagType 'Sensitivity' -TagName 'Confidential' -Doc 'doc-z.docx')
        )
        Export-FixtureCsv -Dir $n -Name 'renamed-export.csv' -Rows @(
            (Get-SpoRow -TagType 'Sensitivity' -TagName 'Confidential' -Doc 'doc-z.docx')
        )
        Compare-ExportDelta -Old $o -New $n | Should -BeNullOrEmpty
    }
    It 'treats item-identity case drift between runs as the same item, not a change' {
        $o = Join-Path $TestDrive 'delta-case-old'
        $n = Join-Path $TestDrive 'delta-case-new'
        Export-FixtureCsv -Dir $o -Name 'items_Sensitivity_Confidential.csv' -Rows @(
            (Get-FixtureRow -TagType 'Sensitivity' -TagName 'Confidential' -Workload 'SPO' `
                -FileUrl 'https://contoso.sharepoint.com/Sites/HR/doc.docx' -FileName 'doc.docx')
        )
        Export-FixtureCsv -Dir $n -Name 'items_Sensitivity_Confidential.csv' -Rows @(
            (Get-FixtureRow -TagType 'Sensitivity' -TagName 'Confidential' -Workload 'SPO' `
                -FileUrl 'https://contoso.sharepoint.com/sites/hr/doc.docx' -FileName 'doc.docx')
        )
        Compare-ExportDelta -Old $o -New $n | Should -BeNullOrEmpty
    }
    It 'ignores CSVs lacking TagType/TagName instead of falling back to the filename' {
        $o = Join-Path $TestDrive 'delta-foreign-old'
        $n = Join-Path $TestDrive 'delta-foreign-new'
        # Old side: a column-less foreign CSV only. New side: a real export of the same item.
        Export-FixtureCsv -Dir $o -Name 'items_Sensitivity_Confidential.csv' -Rows @(
            @{ Location = 'SPO'; SomeColumn = 'x' }
        )
        Export-FixtureCsv -Dir $n -Name 'items_Sensitivity_Confidential.csv' -Rows @(
            (Get-SpoRow -TagType 'Sensitivity' -TagName 'Confidential' -Doc 'doc-a.docx')
        )
        # The foreign CSV contributes nothing, so doc-a appears as Added (not Reclassified
        # against a phantom filename-derived tag).
        $d = @(Compare-ExportDelta -Old $o -New $n)
        $d.Count    | Should -Be 1
        $d[0].Change | Should -Be 'Added'
    }
}
