function Get-GuestExposure {
    <#
    .SYNOPSIS
        Inventories the tenant's guest (external) users and flags the stale ones -
        the lingering external access nobody remembers, and a top Copilot risk.

    .DESCRIPTION
        Copilot surfaces content to whoever can already reach it, and guests are the
        access most often forgotten. This lists every guest, where they came from
        (their external domain), whether they ever accepted the invite, and - when
        the tenant allows it - when they last signed in, so you can see who is dormant.

        Reads Microsoft Graph through the current PnP connection, so run
        Connect-CopilotGovernance first (to the admin URL or any site). Read-only.

        Sign-in based staleness needs Entra ID P1 + the Graph AuditLog.Read.All
        permission. If that is not available the cmdlet degrades automatically and
        falls back to the invitation state (an unaccepted invite is treated as stale),
        with a warning so you are never misled.

        Prereqs (delegated Graph permissions on your Entra app):
          User.Read.All        - list guests (required)
          AuditLog.Read.All    - last sign-in date (optional, for real staleness)

    .PARAMETER StaleDays
        A guest whose last sign-in is older than this many days is flagged stale
        (default 90). Only applies when sign-in data is available.

    .PARAMETER StaleOnly
        Return only the guests flagged stale.

    .EXAMPLE
        Connect-CopilotGovernance -Url "https://contoso-admin.sharepoint.com" -ClientId $cid
        Get-GuestExposure | Format-Table -Auto

    .EXAMPLE
        Get-GuestExposure -StaleOnly -StaleDays 60 | Export-Csv stale-guests.csv -NoTypeInformation
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [int]$StaleDays = 90,
        [switch]$StaleOnly
    )

    $now    = (Get-Date)
    $select = 'id,displayName,mail,userPrincipalName,createdDateTime,externalUserState'

    # Page through @odata.nextLink. Invoke-PnPGraphMethod raises a NON-terminating
    # error on a permission failure, so force -ErrorAction Stop to make try/catch work.
    function Get-CGGuests([string]$startUrl) {
        $list = [System.Collections.Generic.List[object]]::new()
        $url = $startUrl
        while ($url) {
            $resp = Invoke-PnPGraphMethod -Url $url -Method Get -Verbose:$false -ErrorAction Stop
            if ($resp.value) { foreach ($u in $resp.value) { $list.Add($u) } }
            $url = $resp.'@odata.nextLink'
        }
        return $list
    }

    # 1. Guest list - reliable, needs only User.Read.All. Never fold signInActivity
    #    into this query; Graph is finicky about the combination and can blank the
    #    whole result set instead of erroring.
    $guests = Get-CGGuests "v1.0/users?`$filter=userType eq 'Guest'&`$select=$select&`$top=999"

    # 2. Best-effort sign-in enrichment in a SEPARATE query (needs Entra ID P1 +
    #    AuditLog.Read.All). If refused, degrade to invitation-state staleness.
    $signIn    = @{}
    $useSignIn = $false
    try {
        $si = Get-CGGuests "v1.0/users?`$filter=userType eq 'Guest'&`$select=id,signInActivity&`$top=999"
        foreach ($u in $si) { $signIn[$u.id] = $u.signInActivity }
        $useSignIn = $true
    }
    catch {
        Write-Warning "Sign-in activity unavailable (needs Entra ID P1 + AuditLog.Read.All). Using invitation state for staleness instead."
    }

    $results = foreach ($g in $guests) {
        # External domain: prefer the mail domain, else parse the #EXT# UPN.
        $domain =
            if ($g.mail) { ($g.mail -split '@')[-1] }
            elseif ($g.userPrincipalName -match '#EXT#') { (($g.userPrincipalName -split '_')[-1] -split '#')[0] }
            else { '' }

        $invited = if ($g.createdDateTime) { [datetime]$g.createdDateTime } else { $null }
        $invitedDaysAgo = if ($invited) { [int]($now - $invited).TotalDays } else { $null }

        $lastSignIn = $null; $daysSinceSignIn = $null; $neverSignedIn = $null
        if ($useSignIn) {
            $sia = $signIn[$g.id]
            if ($sia -and $sia.lastSignInDateTime) {
                $lastSignIn      = [datetime]$sia.lastSignInDateTime
                $daysSinceSignIn = [int]($now - $lastSignIn).TotalDays
                $neverSignedIn   = $false
            }
            else { $neverSignedIn = $true }
        }

        $stale =
            if ($useSignIn) {
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

    $all = @($results)
    if ($StaleOnly) { $all = @($all | Where-Object { $_.Stale }) }

    $staleCount = @($all | Where-Object { $_.Stale }).Count
    $note = if (-not $useSignIn) { ' (by invitation state - add Entra ID P1 + AuditLog.Read.All for sign-in based staleness)' } else { '' }
    Write-Host ""
    Write-Host ("  {0} guest(s), {1} stale{2}." -f $all.Count, $staleCount, $note) -ForegroundColor Yellow
    Write-Host "  Useful? Star: https://github.com/gvijaikumar9/CopilotGovernance  |  Feedback: Send-CopilotGovernanceFeedback" -ForegroundColor DarkCyan

    return $all
}
