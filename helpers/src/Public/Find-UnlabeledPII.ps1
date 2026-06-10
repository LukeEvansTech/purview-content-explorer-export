function Find-UnlabeledPII {
    <#
    .SYNOPSIS
        Find items flagged as containing PII (by Purview classifiers) that have no sensitivity
        label applied.

    .DESCRIPTION
        Reads the per-tag CSV files produced by purview-content-explorer-export. Labels and PII
        hits are identified from the row data, never from filenames:

        - an item is labelled when any of its rows carries a non-empty SensitivityLabel value
          (the exporter writes the applied label's GUID on every row, whatever was swept), or
          when it appears under a row whose TagType is 'Sensitivity';
        - a row is a PII hit when its TagName matches one of -PIIClassifier (wildcards allowed).

        Items are identified by FileUrl (SPO/ODB) falling back to FileSourceUrl+FileName
        (EXO/Teams) - the cmdlet's Location column duplicates Workload and is NOT an item
        identity. An item is reported only when it appears under a PII classifier and never under
        a sensitivity label. When an item matches more than one PII classifier the names are
        joined. The items_all.csv roll-up is skipped; files lacking the TagType column and rows
        with no derivable item identity are ignored.

    .PARAMETER Path
        Folder containing the per-tag CSV files (one CSV per Purview tag).

    .PARAMETER PIIClassifier
        Name(s) of the Purview PII classifier(s) to inspect, matched against each row's TagName
        with -like (so '*Social Security*' works). Defaults to a set of common built-ins.

    .EXAMPLE
        Find-UnlabeledPII -Path ./output/

    .OUTPUTS
        PSCustomObject for each unlabelled PII item.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [string[]]$PIIClassifier = @(
            'All Full Names',
            'EU Debit Card Number',
            'U.S. Social Security Number (SSN)',
            'EU Driver''s License Number',
            'PII (default - All)'
        )
    )

    Write-Verbose "Reading exports from $Path"

    $allCsv = @(Get-CEPerTagCsvFile -Path $Path)
    if ($allCsv.Count -eq 0) {
        Write-Warning "No CSV files found in $Path"
        return
    }

    $labelled  = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $piiByItem = [ordered]@{}   # item identity -> @{ Classifiers; Workload; FileName; FileUrl; FileSourceUrl; LastModifiedTime }

    foreach ($csv in $allCsv) {
        $rows = @(Import-Csv $csv.FullName)
        if ($rows.Count -eq 0) { continue }
        # Column set is identical for every row of one CSV - check once per file.
        $cols = $rows[0].PSObject.Properties.Name
        if ($cols -notcontains 'TagType') { continue }
        $hasTagName   = $cols -contains 'TagName'
        $hasWorkload  = $cols -contains 'Workload'
        $hasFileName  = $cols -contains 'FileName'
        $hasFileUrl   = $cols -contains 'FileUrl'
        $hasFileSrc   = $cols -contains 'FileSourceUrl'
        $hasModified  = $cols -contains 'LastModifiedTime'
        $hasSensLabel = $cols -contains 'SensitivityLabel'

        foreach ($row in $rows) {
            $key = Get-CEItemIdentity -Row $row
            if (-not $key) { continue }

            # The per-row SensitivityLabel GUID is authoritative for label-ness whatever was
            # swept; a TagType of 'Sensitivity' marks the row as part of a label sweep.
            if ($hasSensLabel -and -not [string]::IsNullOrEmpty([string]$row.SensitivityLabel)) {
                [void]$labelled.Add($key)
            }
            if ($row.TagType -eq 'Sensitivity') {
                [void]$labelled.Add($key)
                continue
            }

            if (-not $hasTagName) { continue }
            $name = [string]$row.TagName
            $isPii = $false
            foreach ($pattern in $PIIClassifier) {
                if ($name -like $pattern) { $isPii = $true; break }
            }
            if (-not $isPii) { continue }

            if (-not $piiByItem.Contains($key)) {
                $piiByItem[$key] = @{
                    Classifiers      = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
                    Workload         = $(if ($hasWorkload) { [string]$row.Workload } else { '' })
                    FileName         = $(if ($hasFileName) { [string]$row.FileName } else { '' })
                    FileUrl          = $(if ($hasFileUrl)  { [string]$row.FileUrl }  else { '' })
                    FileSourceUrl    = $(if ($hasFileSrc)  { [string]$row.FileSourceUrl } else { '' })
                    LastModifiedTime = $(if ($hasModified) { [string]$row.LastModifiedTime } else { '' })
                }
            }
            [void]$piiByItem[$key].Classifiers.Add($name)
        }
    }

    if ($piiByItem.Count -eq 0) {
        Write-Warning "No rows matched the PII classifier(s); nothing to inspect."
        return
    }

    foreach ($key in $piiByItem.Keys) {
        if ($labelled.Contains($key)) { continue }
        $info = $piiByItem[$key]
        [PSCustomObject]@{
            PSTypeName       = 'PurviewContentExplorerHelpers.UnlabeledPII'
            Classifier       = (($info.Classifiers | Sort-Object) -join ', ')
            Workload         = $info.Workload
            FileName         = $info.FileName
            FileUrl          = $info.FileUrl
            FileSourceUrl    = $info.FileSourceUrl
            LastModifiedTime = $info.LastModifiedTime
        }
    }
}
