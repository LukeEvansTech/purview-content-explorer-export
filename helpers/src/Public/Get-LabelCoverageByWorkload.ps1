function Get-LabelCoverageByWorkload {
    <#
    .SYNOPSIS
        Compute sensitivity-label coverage rates broken down by Microsoft 365 workload.

    .DESCRIPTION
        Reads per-tag CSV exports produced by purview-content-explorer-export. Coverage is computed
        from the row data, never from filenames: items are identified by FileUrl (SPO/ODB) falling
        back to FileSourceUrl+FileName (EXO/Teams) - the cmdlet's Location column duplicates
        Workload and is NOT an item identity. Items are de-duplicated per workload, and an item
        counts as labelled when any of its rows carries a non-empty SensitivityLabel value (the
        exporter writes the applied label's GUID on every row, whatever was swept) or appears
        under a row whose TagType is 'Sensitivity'.

        The denominator is every distinct item in the folder, so include whatever sweeps define
        "items worth labelling". The items_all.csv roll-up is skipped (it duplicates every
        per-tag row); files lacking the TagType/Workload columns and rows with no derivable item
        identity are ignored.

    .PARAMETER Path
        Folder containing the per-tag CSV files.

    .EXAMPLE
        Get-LabelCoverageByWorkload -Path ./output/ | Format-Table

    .OUTPUTS
        PSCustomObject per workload.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path
    )

    Write-Verbose "Reading exports from $Path"

    # workload -> @{ All = distinct item identities; Labelled = those seen under a Sensitivity tag }
    $byWorkload = @{}

    foreach ($csv in @(Get-CEPerTagCsvFile -Path $Path)) {
        $rows = @(Import-Csv $csv.FullName)
        if ($rows.Count -eq 0) { continue }
        # Column set is identical for every row of one CSV - check once per file.
        $cols = $rows[0].PSObject.Properties.Name
        if ($cols -notcontains 'Workload' -or $cols -notcontains 'TagType') { continue }
        $hasSensLabel = $cols -contains 'SensitivityLabel'

        foreach ($row in $rows) {
            $w = [string]$row.Workload
            if ([string]::IsNullOrEmpty($w)) { continue }
            $key = Get-CEItemIdentity -Row $row
            if (-not $key) { continue }

            if (-not $byWorkload.ContainsKey($w)) {
                $byWorkload[$w] = @{
                    All      = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
                    Labelled = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
                }
            }
            [void]$byWorkload[$w].All.Add($key)
            # The per-row SensitivityLabel GUID is authoritative for label-ness whatever was
            # swept; a TagType of 'Sensitivity' marks the row as part of a label sweep.
            if (($row.TagType -eq 'Sensitivity') -or
                ($hasSensLabel -and -not [string]::IsNullOrEmpty([string]$row.SensitivityLabel))) {
                [void]$byWorkload[$w].Labelled.Add($key)
            }
        }
    }

    foreach ($w in $byWorkload.Keys | Sort-Object) {
        $total    = $byWorkload[$w].All.Count
        $labelled = $byWorkload[$w].Labelled.Count
        [PSCustomObject]@{
            PSTypeName  = 'PurviewContentExplorerHelpers.LabelCoverage'
            Workload    = $w
            TotalItems  = $total
            Labelled    = $labelled
            Unlabelled  = $total - $labelled
            CoveragePct = [math]::Round(($labelled / [math]::Max($total, 1)) * 100, 1)
        }
    }
}
