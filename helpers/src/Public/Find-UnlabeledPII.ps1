function Find-UnlabeledPII {
    <#
    .SYNOPSIS
        Find items flagged as containing PII (by Purview classifiers) that have no sensitivity
        label applied.

    .DESCRIPTION
        Reads the per-tag CSV files produced by purview-content-explorer-export and joins items
        across the PII-classifier tags with the sensitivity-label tags. Returns the items that
        appear under a PII classifier but not under any sensitivity-label tag.

    .PARAMETER Path
        Folder containing the per-tag CSV files (one CSV per Purview tag).

    .PARAMETER PIIClassifier
        Name(s) of the Purview PII classifier(s) to inspect. Defaults to the common built-ins.

    .EXAMPLE
        Find-UnlabeledPII -Path ./exports/2026-05/

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

    $allCsv = Get-ChildItem -Path $resolved -Filter '*.csv' -File
    if (-not $allCsv) {
        Write-Warning "No CSV files found in $resolved"
        return
    }

    # Heuristic: any CSV whose name matches a sensitivity-label tag pattern.
    $labelTagPattern = '^(public|internal|confidential|restricted|highly confidential|general)'
    $piiTagPattern   = ($PIIClassifier | ForEach-Object { [regex]::Escape($_) }) -join '|'

    $piiCsv     = $allCsv | Where-Object { $_.BaseName -match $piiTagPattern }
    $labelCsv   = $allCsv | Where-Object { $_.BaseName -match $labelTagPattern }

    if (-not $piiCsv) {
        Write-Warning "No CSV files matched the PII-classifier pattern; nothing to inspect."
        return
    }

    $labelledKeys = @{}
    foreach ($csv in $labelCsv) {
        Import-Csv $csv.FullName | ForEach-Object {
            if ($_.PSObject.Properties.Name -contains 'Location') {
                $labelledKeys[$_.Location] = $true
            }
        }
    }

    foreach ($csv in $piiCsv) {
        Import-Csv $csv.FullName | Where-Object {
            $_.PSObject.Properties.Name -contains 'Location' -and
            -not $labelledKeys.ContainsKey($_.Location)
        } | ForEach-Object {
            [PSCustomObject]@{
                PSTypeName = 'PurviewContentExplorerHelpers.UnlabeledPII'
                Classifier = $csv.BaseName
                Location   = $_.Location
                Workload   = $_.Workload
                ItemSize   = $_.ItemSize
                Modified   = $_.Modified
            }
        }
    }
}
