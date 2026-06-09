function Compare-ExportDelta {
    <#
    .SYNOPSIS
        Diff two purview-content-explorer-export runs.

    .DESCRIPTION
        Compares two folders of per-tag CSV exports and surfaces items that appeared, disappeared,
        or moved between tags between the two runs. Uses Location as the join key. Each item's tag
        set is taken from the rows' TagType/TagName columns ('TagType/TagName'), falling back to the
        CSV BaseName for rows that lack those columns, so the diff is independent of how the files
        are named.

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
            $baseName = $_.BaseName
            Import-Csv $_.FullName | ForEach-Object {
                $props = $_.PSObject.Properties.Name
                if ($props -notcontains 'Location') { return }
                $loc = [string]$_.Location
                if ([string]::IsNullOrEmpty($loc)) { return }
                $tag = if (($props -contains 'TagType') -and ($props -contains 'TagName')) {
                    "$($_.TagType)/$($_.TagName)"
                } else {
                    $baseName
                }
                if (-not $snap.ContainsKey($loc)) {
                    $snap[$loc] = [System.Collections.Generic.HashSet[string]]::new()
                }
                [void]$snap[$loc].Add($tag)
            }
        }
        return $snap
    }

    $oldSnap = Read-Snapshot $Old
    $newSnap = Read-Snapshot $New

    # Cast Keys to [string[]]: a hashtable's KeyCollection is non-generic IEnumerable,
    # which does not satisfy the HashSet[string](IEnumerable[string]) constructor overload.
    $allLocations = [System.Collections.Generic.HashSet[string]]::new([string[]]$oldSnap.Keys)
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
