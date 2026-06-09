function Compare-ExportDelta {
    <#
    .SYNOPSIS
        Diff two purview-content-explorer-export runs.

    .DESCRIPTION
        Compares two folders of per-tag CSV exports and surfaces items that appeared, disappeared,
        or moved between tags between the two runs. Uses Location as the join key and tag (CSV
        BaseName) as the categorisation.

    .PARAMETER Old
        Folder containing the earlier export.

    .PARAMETER New
        Folder containing the later export.

    .EXAMPLE
        Compare-ExportDelta -Old ./exports/2026-04/ -New ./exports/2026-05/

    .OUTPUTS
        PSCustomObject for each changed item with Change ('Added','Removed','Reclassified').
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Old,
        [Parameter(Mandatory)][string]$New
    )

    function Read-Snapshot([string]$path) {
        $snap = @{}
        Get-ChildItem -Path (Resolve-Path $path) -Filter '*.csv' -File | ForEach-Object {
            $tag = $_.BaseName
            Import-Csv $_.FullName | ForEach-Object {
                if ($_.PSObject.Properties.Name -contains 'Location') {
                    if (-not $snap.ContainsKey($_.Location)) {
                        $snap[$_.Location] = [System.Collections.Generic.HashSet[string]]::new()
                    }
                    [void]$snap[$_.Location].Add($tag)
                }
            }
        }
        return $snap
    }

    $oldSnap = Read-Snapshot $Old
    $newSnap = Read-Snapshot $New

    $allLocations = [System.Collections.Generic.HashSet[string]]::new($oldSnap.Keys)
    foreach ($k in $newSnap.Keys) { [void]$allLocations.Add($k) }

    foreach ($loc in $allLocations) {
        $inOld = $oldSnap.ContainsKey($loc)
        $inNew = $newSnap.ContainsKey($loc)

        if ($inOld -and -not $inNew) {
            [PSCustomObject]@{ Location = $loc; Change = 'Removed'; OldTags = ($oldSnap[$loc] -join ','); NewTags = '' }
        } elseif ($inNew -and -not $inOld) {
            [PSCustomObject]@{ Location = $loc; Change = 'Added';   OldTags = '';                          NewTags = ($newSnap[$loc] -join ',') }
        } elseif (-not $oldSnap[$loc].SetEquals($newSnap[$loc])) {
            [PSCustomObject]@{ Location = $loc; Change = 'Reclassified'; OldTags = ($oldSnap[$loc] -join ','); NewTags = ($newSnap[$loc] -join ',') }
        }
    }
}
