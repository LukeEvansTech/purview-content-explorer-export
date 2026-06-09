function Find-UnlabeledPII {
    <#
    .SYNOPSIS
        Find items flagged as containing PII (by Purview classifiers) that have no sensitivity
        label applied.

    .DESCRIPTION
        Reads the per-tag CSV files produced by purview-content-explorer-export. Each row carries
        TagType / TagName / Workload / Location columns, so PII items and labelled items are
        identified from the row data rather than from filenames:

        - a row is a sensitivity label when its TagType is 'Sensitivity';
        - a row is a PII hit when its TagName matches one of -PIIClassifier (wildcards allowed).

        Returns one object per distinct PII item (keyed by Location) that never appears under a
        Sensitivity tag. When an item matches more than one PII classifier the names are joined.

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

    $resolved = Resolve-Path $Path
    Write-Verbose "Reading exports from $resolved"

    $allCsv = @(Get-ChildItem -Path $resolved -Filter '*.csv' -File)
    if ($allCsv.Count -eq 0) {
        Write-Warning "No CSV files found in $resolved"
        return
    }

    $labelled = [System.Collections.Generic.HashSet[string]]::new()
    $piiByLoc = [ordered]@{}   # Location -> @{ Classifiers; Workload; ItemSize; Modified }

    foreach ($csv in $allCsv) {
        Import-Csv $csv.FullName | ForEach-Object {
            $props = $_.PSObject.Properties.Name
            if ($props -notcontains 'Location' -or $props -notcontains 'TagType') { return }
            $loc = [string]$_.Location
            if ([string]::IsNullOrEmpty($loc)) { return }

            if ($_.TagType -eq 'Sensitivity') {
                [void]$labelled.Add($loc)
                return
            }

            if ($props -notcontains 'TagName') { return }
            $name = [string]$_.TagName
            $isPii = $false
            foreach ($pattern in $PIIClassifier) {
                if ($name -like $pattern) { $isPii = $true; break }
            }
            if (-not $isPii) { return }

            if (-not $piiByLoc.Contains($loc)) {
                $piiByLoc[$loc] = @{
                    Classifiers = [System.Collections.Generic.HashSet[string]]::new()
                    Workload    = $(if ($props -contains 'Workload') { [string]$_.Workload } else { '' })
                    ItemSize    = $(if ($props -contains 'ItemSize') { [string]$_.ItemSize } else { '' })
                    Modified    = $(if ($props -contains 'Modified') { [string]$_.Modified } else { '' })
                }
            }
            [void]$piiByLoc[$loc].Classifiers.Add($name)
        }
    }

    if ($piiByLoc.Count -eq 0) {
        Write-Warning "No rows matched the PII classifier(s); nothing to inspect."
        return
    }

    foreach ($loc in $piiByLoc.Keys) {
        if ($labelled.Contains($loc)) { continue }
        $info = $piiByLoc[$loc]
        [PSCustomObject]@{
            PSTypeName = 'PurviewContentExplorerHelpers.UnlabeledPII'
            Classifier = (($info.Classifiers | Sort-Object) -join ', ')
            Location   = $loc
            Workload   = $info.Workload
            ItemSize   = $info.ItemSize
            Modified   = $info.Modified
        }
    }
}
