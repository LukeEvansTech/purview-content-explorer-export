function Compare-ExportDelta {
    <#
    .SYNOPSIS
        Diff two purview-content-explorer-export runs.

    .DESCRIPTION
        Compares two folders of per-tag CSV exports and surfaces items that appeared, disappeared,
        or moved between tags between the two runs. Items are identified by FileUrl (SPO/ODB)
        falling back to FileSourceUrl+FileName (EXO/Teams) - the cmdlet's Location column
        duplicates Workload and is NOT an item identity. Each item's tag set is taken from the
        rows' TagType/TagName columns ('TagType/TagName'), so the diff is independent of how the
        files are named (a renamed export is not a change). The items_all.csv roll-up is skipped;
        files lacking the TagType/TagName columns and rows with no derivable item identity are
        ignored.

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
        $snap = @{}   # item identity -> HashSet of 'TagType/TagName' (hashtable keys are case-insensitive)
        foreach ($csv in @(Get-CEPerTagCsvFile -Path $path)) {
            $rows = @(Import-Csv $csv.FullName)
            if ($rows.Count -eq 0) { continue }
            # Column set is identical for every row of one CSV - check once per file.
            $cols = $rows[0].PSObject.Properties.Name
            if ($cols -notcontains 'TagType' -or $cols -notcontains 'TagName') { continue }

            foreach ($row in $rows) {
                $key = Get-CEItemIdentity -Row $row
                if (-not $key) { continue }
                $tag = '{0}/{1}' -f $row.TagType, $row.TagName
                if (-not $snap.ContainsKey($key)) {
                    $snap[$key] = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
                }
                [void]$snap[$key].Add($tag)
            }
        }
        return $snap
    }

    $oldSnap = Read-Snapshot $Old
    $newSnap = Read-Snapshot $New

    # Cast Keys to [string[]]: a hashtable's KeyCollection is non-generic IEnumerable, which does
    # not satisfy the HashSet[string](IEnumerable[string], comparer) constructor overload.
    $everyItem = [System.Collections.Generic.HashSet[string]]::new([string[]]$oldSnap.Keys, [System.StringComparer]::OrdinalIgnoreCase)
    foreach ($k in $newSnap.Keys) { [void]$everyItem.Add($k) }

    foreach ($item in $everyItem) {
        $inOld = $oldSnap.ContainsKey($item)
        $inNew = $newSnap.ContainsKey($item)

        if ($inOld -and -not $inNew) {
            [PSCustomObject]@{ Item = $item; Change = 'Removed'; OldTags = ($oldSnap[$item] -join ', '); NewTags = '' }
        } elseif ($inNew -and -not $inOld) {
            [PSCustomObject]@{ Item = $item; Change = 'Added';   OldTags = '';                            NewTags = ($newSnap[$item] -join ', ') }
        } elseif (-not $oldSnap[$item].SetEquals($newSnap[$item])) {
            [PSCustomObject]@{ Item = $item; Change = 'Reclassified'; OldTags = ($oldSnap[$item] -join ', '); NewTags = ($newSnap[$item] -join ', ') }
        }
    }
}
