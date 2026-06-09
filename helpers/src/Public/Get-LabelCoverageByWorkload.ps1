function Get-LabelCoverageByWorkload {
    <#
    .SYNOPSIS
        Compute sensitivity-label coverage rates broken down by Microsoft 365 workload.

    .DESCRIPTION
        Reads per-tag CSV exports produced by purview-content-explorer-export. Aggregates total
        items per workload and the subset bearing any sensitivity label, then emits a coverage
        percentage per workload.

    .PARAMETER Path
        Folder containing the per-tag CSV files.

    .EXAMPLE
        Get-LabelCoverageByWorkload -Path ./exports/2026-05/ | Format-Table

    .OUTPUTS
        PSCustomObject per workload.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path
    )

    $resolved = Resolve-Path $Path
    $labelTagPattern = '^(public|internal|confidential|restricted|highly confidential|general)'

    $byWorkload = @{}

    Get-ChildItem -Path $resolved -Filter '*.csv' -File | ForEach-Object {
        $isLabelTag = $_.BaseName -match $labelTagPattern
        Import-Csv $_.FullName | ForEach-Object {
            $w = $_.Workload
            if (-not $byWorkload.ContainsKey($w)) {
                $byWorkload[$w] = @{ Total = 0; Labelled = 0 }
            }
            $byWorkload[$w].Total++
            if ($isLabelTag) {
                $byWorkload[$w].Labelled++
            }
        }
    }

    foreach ($w in $byWorkload.Keys | Sort-Object) {
        $total    = $byWorkload[$w].Total
        $labelled = $byWorkload[$w].Labelled
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
