# Internal helpers for the SharePoint "pseudo-principal" claims that Copilot cares
# about most: Everyone, and Everyone Except External Users (EEEU).
#
# Login names:
#   Everyone                         -> c:0(.s|true
#   Everyone except external users   -> c:0-.f|rolemanager|spo-grid-all-users/{tenantId}
# The EEEU login carries the tenant id, so we match on the stable 'spo-grid-all-users'
# fragment rather than an exact string.

function Get-CGClaim {
    [CmdletBinding()]
    param(
        [ValidateSet('Everyone', 'EveryoneExceptExternal', 'Both')]
        [string]$ClaimType = 'Both'
    )

    $everyone = [pscustomobject]@{ Name = 'Everyone';                       Kind = 'Exact'; Match = 'c:0(.s|true' }
    $eeeu     = [pscustomobject]@{ Name = 'Everyone except external users'; Kind = 'Like';  Match = 'spo-grid-all-users' }

    switch ($ClaimType) {
        'Everyone'               { , @($everyone) }
        'EveryoneExceptExternal' { , @($eeeu) }
        default                  { , @($everyone, $eeeu) }
    }
}

function Test-CGClaimLogin {
    [CmdletBinding()]
    param(
        [string]$LoginName,
        [object[]]$Claims
    )
    if ([string]::IsNullOrEmpty($LoginName)) { return $null }
    foreach ($c in $Claims) {
        if ($c.Kind -eq 'Exact') {
            if ($LoginName -eq $c.Match) { return $c.Name }
        }
        else {
            if ($LoginName -like "*$($c.Match)*") { return $c.Name }
        }
    }
    return $null
}
