# CEHelpers.psm1 — pure helper functions for Content Explorer sweep scripts.
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
    $included = ($NameLike.Count -eq 0) -or ($NameLike | Where-Object { $Name -like $_ }).Count -gt 0
    if (-not $included) { return $false }
    $excluded = ($NameNotLike | Where-Object { $Name -like $_ }).Count -gt 0
    return -not $excluded
}

Export-ModuleMember -Function Get-CESafeName, Test-CETagNameFilter
