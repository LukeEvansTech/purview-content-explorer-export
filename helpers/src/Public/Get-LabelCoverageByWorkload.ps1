function Get-LabelCoverageByWorkload {
    <#
    .SYNOPSIS
        Compute sensitivity-label coverage rates broken down by Microsoft 365 workload.

    .DESCRIPTION
        Reads per-tag CSV exports produced by purview-content-explorer-export. Each row carries
        TagType / TagName / Workload / Location columns, so coverage is computed from the row data
        rather than from filenames: items are de-duplicated by (Workload, Location), and an item
        counts as labelled when it appears in any row whose TagType is 'Sensitivity'. Emits a
        coverage percentage per workload.

        For coverage to be meaningful the export folder must contain both the Sensitivity-label
        sweep and whatever other tags you want counted in the denominator. Rows without a Workload
        or Location value (e.g. a header-only empty export) are ignored.

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

    $resolved = Resolve-Path $Path
    Write-Verbose "Reading exports from $resolved"

    # workload -> @{ All = distinct Locations; Labelled = distinct Locations with a Sensitivity tag }
    $byWorkload = @{}

    Get-ChildItem -Path $resolved -Filter '*.csv' -File | ForEach-Object {
        Import-Csv $_.FullName | ForEach-Object {
            $props = $_.PSObject.Properties.Name
            if ($props -notcontains 'Workload' -or $props -notcontains 'Location') { return }
            $w = $_.Workload
            if ([string]::IsNullOrEmpty($w)) { return }

            if (-not $byWorkload.ContainsKey($w)) {
                $byWorkload[$w] = @{
                    All      = [System.Collections.Generic.HashSet[string]]::new()
                    Labelled = [System.Collections.Generic.HashSet[string]]::new()
                }
            }
            [void]$byWorkload[$w].All.Add([string]$_.Location)
            if (($props -contains 'TagType') -and ($_.TagType -eq 'Sensitivity')) {
                [void]$byWorkload[$w].Labelled.Add([string]$_.Location)
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
