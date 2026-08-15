# Builds one guest record from a raw Graph user object. Pure and side-effect free
# so it can be unit tested without a tenant. Domain comes from the mail address, or
# is parsed out of the #EXT# guest UPN. Staleness is sign-in based when sign-in data
# is available, otherwise it falls back to the invitation state.

function ConvertTo-CGGuestRecord {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][object]$Guest,
        [object]$SignInActivity,   # the guest's signInActivity object, or $null
        [bool]$UseSignIn,          # whether sign-in data is available at all
        [int]$StaleDays = 90,
        [datetime]$Now = (Get-Date)
    )

    $g = $Guest

    $domain =
        if ($g.mail) { ($g.mail -split '@')[-1] }
        elseif ($g.userPrincipalName -match '#EXT#') { (($g.userPrincipalName -split '_')[-1] -split '#')[0] }
        else { '' }

    $invited        = if ($g.createdDateTime) { [datetime]$g.createdDateTime } else { $null }
    $invitedDaysAgo = if ($invited) { [int]($Now - $invited).TotalDays } else { $null }

    $lastSignIn = $null; $daysSinceSignIn = $null; $neverSignedIn = $null
    if ($UseSignIn) {
        if ($SignInActivity -and $SignInActivity.lastSignInDateTime) {
            $lastSignIn      = [datetime]$SignInActivity.lastSignInDateTime
            $daysSinceSignIn = [int]($Now - $lastSignIn).TotalDays
            $neverSignedIn   = $false
        }
        else { $neverSignedIn = $true }
    }

    $stale =
        if ($UseSignIn) {
            ($neverSignedIn -eq $true) -or ($null -ne $daysSinceSignIn -and $daysSinceSignIn -gt $StaleDays)
        }
        else {
            $g.externalUserState -eq 'PendingAcceptance'   # never accepted the invite
        }

    [pscustomobject]@{
        DisplayName     = $g.displayName
        Email           = if ($g.mail) { $g.mail } else { $g.userPrincipalName }
        ExternalDomain  = $domain
        InviteState     = $g.externalUserState
        InvitedDaysAgo  = $invitedDaysAgo
        LastSignIn      = $lastSignIn
        DaysSinceSignIn = $daysSinceSignIn
        NeverSignedIn   = $neverSignedIn
        Stale           = [bool]$stale
    }
}
