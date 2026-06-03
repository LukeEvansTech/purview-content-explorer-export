# CEHelpers.psm1 - pure helper functions for Content Explorer sweep scripts.
# Cmdlet-calling logic lives in the top-level scripts; this module is offline-testable.

function Get-CESafeName {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position=0)]
        [AllowEmptyString()]
        [string]$Name
    )
    return [regex]::Replace($Name, '[^A-Za-z0-9._-]', '_')
}

function Test-CETagNameFilter {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$NameLike,
        [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$NameNotLike
    )
    # Wrap pipeline results in @() before .Count: on Windows PowerShell 5.1 a Where-Object
    # that matches nothing returns $null, and $null.Count throws under Set-StrictMode -Latest.
    # @(...) coerces to an array so .Count is always 0+. (PS 7 tolerates it either way.)
    $included = ($NameLike.Count -eq 0) -or @($NameLike | Where-Object { $Name -like $_ }).Count -gt 0
    if (-not $included) { return $false }
    $excluded = @($NameNotLike | Where-Object { $Name -like $_ }).Count -gt 0
    return -not $excluded
}

function Get-CETagTypeEnumeration {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Retention','SensitiveInformationType','Sensitivity','TrainableClassifier')]
        [string]$TagType
    )
    switch ($TagType) {
        'SensitiveInformationType' { @{ Cmdlet = 'Get-DlpSensitiveInformationType'; NameProperty = 'Name' } }
        'Sensitivity'              { @{ Cmdlet = 'Get-Label';                       NameProperty = 'DisplayName' } }
        'Retention'                { @{ Cmdlet = 'Get-ComplianceTag';               NameProperty = 'Name' } }
        'TrainableClassifier'      { @{ Cmdlet = 'Get-DlpTrainableClassifier';      NameProperty = 'Name' } }
    }
}

function Get-CEConfidenceSummary {
    # Summarise the per-SIT confidence counts in a Content Explorer item's
    # SensitiveInfoTypesData JSON into two sortable labels:
    #   ItemMaxConfidence - strongest confidence of ANY SIT in the item.
    #   TargetConfidence  - confidence of the swept SIT (matched by GUID), or
    #                       'N/A' when no GUID is given or it's not in the item
    #                       (e.g. bundle SITs, whose own GUID is absent).
    # Labels are '3-High' / '2-Medium' / '1-Low' / '0-None' so a plain sort
    # orders by strength. Tolerant of empty/malformed input (returns defaults).
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position=0)]
        [AllowEmptyString()]
        [AllowNull()]
        [string]$Data,

        [string]$TargetGuid
    )

    # Highest non-zero bucket for one entry -> ordered label.
    function ConvertTo-CELevel($entry) {
        if ([int]$entry.HighConfidenceMatch   -gt 0) { return '3-High' }
        if ([int]$entry.MediumConfidenceMatch -gt 0) { return '2-Medium' }
        if ([int]$entry.LowConfidenceMatch    -gt 0) { return '1-Low' }
        return '0-None'
    }

    $itemMax = '0-None'
    $target  = 'N/A'

    $entries = @()
    if (-not [string]::IsNullOrWhiteSpace($Data)) {
        try {
            # Drop nulls so member access stays safe under Set-StrictMode -Latest.
            $entries = @($Data | ConvertFrom-Json | Where-Object { $null -ne $_ })
        } catch {
            $entries = @()  # malformed JSON: keep defaults rather than break the export
        }
    }

    $maxRank = 0
    foreach ($e in $entries) {
        $lvl  = ConvertTo-CELevel $e
        $rank = [int]$lvl.Substring(0, 1)
        if ($rank -gt $maxRank) { $maxRank = $rank; $itemMax = $lvl }

        # -eq on strings is case-insensitive in PowerShell.
        if ($TargetGuid -and $e.Id -and ([string]$e.Id -eq $TargetGuid)) {
            $target = $lvl
        }
    }

    return [pscustomobject]@{
        ItemMaxConfidence = $itemMax
        TargetConfidence  = $target
    }
}

function Get-CESitName {
    # Resolve a comma-separated list of SIT GUIDs (the SensitiveInfoTypes column) to a
    # comma-separated list of friendly names, preserving order. Unknown GUIDs fall back to
    # the raw GUID so nothing is silently dropped (e.g. a SIT deleted since the data was made).
    # $NameMap is a GUID -> name hashtable; PowerShell hashtable key lookup is case-insensitive.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position=0)]
        [AllowEmptyString()]
        [AllowNull()]
        [string]$Guids,

        [Parameter(Mandatory, Position=1)]
        [hashtable]$NameMap
    )
    if ([string]::IsNullOrWhiteSpace($Guids)) { return '' }
    $names = foreach ($g in ($Guids -split ',')) {
        $key = $g.Trim()
        if ($key -eq '') { continue }
        $name = $NameMap[$key]
        if ($name) { $name } else { $key }
    }
    return ($names -join ', ')
}

Export-ModuleMember -Function Get-CESafeName, Test-CETagNameFilter, Get-CETagTypeEnumeration, Get-CEConfidenceSummary, Get-CESitName
