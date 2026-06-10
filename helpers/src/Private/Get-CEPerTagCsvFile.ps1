function Get-CEPerTagCsvFile {
    <#
    .SYNOPSIS
        Enumerate the per-tag CSV files in an export folder.

    .DESCRIPTION
        Lists *.csv files in the folder, excluding the items_all.csv roll-up - it duplicates every
        per-tag row, so reading it would parse the whole dataset twice (the orchestrator's own
        roll-up builder excludes it the same way). If the folder contains ONLY items_all.csv,
        it is returned so a kept-roll-up-only folder still works.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path
    )

    $resolved = Resolve-Path $Path
    $allCsv = @(Get-ChildItem -Path $resolved -Filter '*.csv' -File)
    $perTag = @($allCsv | Where-Object { $_.Name -ne 'items_all.csv' })
    if ($perTag.Count -gt 0) {
        return $perTag
    }
    return $allCsv
}
