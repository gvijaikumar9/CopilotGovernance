function Get-EveryoneAccess {
    <#
    .SYNOPSIS
        Finds every place the 'Everyone' or 'Everyone Except External Users' (EEEU)
        claim grants access - the #1 oversharing culprit that M365 Copilot amplifies.

    .DESCRIPTION
        Copilot can surface anything a user can already reach. The broad pseudo-groups
        'Everyone' and 'Everyone except external users' are the most common way content
        ends up reachable by the whole company without anyone intending it.

        This cmdlet walks a site (or the whole tenant) and reports each web- and,
        optionally, list-level permission granted to those claims, along with the
        permission level and a direct URL. Read-only.

        Prereqs: PnP.PowerShell, and a connection (Connect-CopilotGovernance).
        For -AllSites you must be connected to the tenant-admin URL and pass -ClientId
        so each site can be reconnected using your cached token.

    .PARAMETER Site
        A single site collection URL to scan.

    .PARAMETER AllSites
        Scan every site in the tenant (requires an admin connection + -ClientId).

    .PARAMETER ClaimType
        Which claim(s) to hunt for: Everyone, EveryoneExceptExternal, or Both (default).

    .PARAMETER IncludeLists
        Also inspect lists/libraries that have unique (broken-inheritance) permissions.
        Slower, but catches oversharing below the site level.

    .PARAMETER ClientId
        Your PnP Entra app client id (needed to reconnect per-site during -AllSites).

    .EXAMPLE
        Connect-CopilotGovernance -Url "https://contoso.sharepoint.com/sites/hr" -ClientId $cid
        Get-EveryoneAccess -Site "https://contoso.sharepoint.com/sites/hr" -IncludeLists

    .EXAMPLE
        Connect-CopilotGovernance -Url "https://contoso-admin.sharepoint.com" -ClientId $cid
        Get-EveryoneAccess -AllSites -ClientId $cid | Export-Csv everyone-access.csv -NoTypeInformation
    #>
    [CmdletBinding(DefaultParameterSetName = 'Site')]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory, ParameterSetName = 'Site', Position = 0)]
        [string]$Site,

        [Parameter(Mandatory, ParameterSetName = 'AllSites')]
        [switch]$AllSites,

        [ValidateSet('Everyone', 'EveryoneExceptExternal', 'Both')]
        [string]$ClaimType = 'Both',

        [switch]$IncludeLists,

        [switch]$IncludeRootSite,

        [string]$ClientId
    )

    $claims  = Get-CGClaim -ClaimType $ClaimType
    $results = [System.Collections.Generic.List[object]]::new()
    $skippedSites = [System.Collections.Generic.List[string]]::new()  # coverage: sites we couldn't read

    # Work out which sites to scan
    if ($AllSites) {
        if (-not $ClientId) { throw "-AllSites requires -ClientId to reconnect to each site." }
        Write-Verbose "Enumerating tenant sites (admin connection required)..."
        $siteUrls = Get-PnPTenantSite -ErrorAction Stop -Verbose:$false |
            Where-Object {
                $_.Template -notmatch 'Redirect' -and       # redirect (renamed/archived) sites
                $_.Template -notmatch 'SPSMSITEHOST' -and    # the My Site host
                ($IncludeRootSite -or ([System.Uri]$_.Url).AbsolutePath -ne '/')  # tenant root skipped by default (large + rarely the target)
            } |
            Select-Object -ExpandProperty Url
        Write-Verbose ("Found {0} site(s) to scan (root site {1})." -f @($siteUrls).Count, $(if ($IncludeRootSite) { 'included' } else { 'skipped - use -IncludeRootSite' }))
    }
    else {
        $siteUrls = @($Site)
    }

    $total = @($siteUrls).Count
    $i = 0
    foreach ($siteUrl in $siteUrls) {
        $i++
        if ($AllSites) {
            Write-Progress -Activity "Scanning for Everyone/EEEU access" -Status ("{0}/{1}  {2}" -f $i, $total, $siteUrl) -PercentComplete (($i / [Math]::Max($total, 1)) * 100)
            Write-Verbose ("[{0}/{1}] {2}" -f $i, $total, $siteUrl)
        }
        # Connect to the target site if a ClientId is given (so -Site "just works"
        # without a prior Connect); otherwise use the current ambient connection.
        if ($AllSites -or $ClientId) {
            try { Connect-PnPOnline -Url $siteUrl -Interactive -ClientId $ClientId -ErrorAction Stop -Verbose:$false }
            catch { Write-Warning "Could not connect to $siteUrl : $($_.Exception.Message)"; $skippedSites.Add($siteUrl); continue }
        }

        # Scan with bounded retry on transient throttling (HTTP 429/503). Accumulate
        # into a per-site list and only merge on success, so a retry never double-counts.
        $attempt = 0
        while ($true) {
            $attempt++
            $siteFindings = [System.Collections.Generic.List[object]]::new()
            try {
                $ctx = Get-PnPContext -Verbose:$false

                # --- Web-level role assignments ---
                $web = Get-PnPWeb -Includes RoleAssignments, Title, Url -Verbose:$false
                $ctx.Load($web.RoleAssignments)
                $ctx.ExecuteQuery()
                foreach ($ra in $web.RoleAssignments) { $ctx.Load($ra.Member); $ctx.Load($ra.RoleDefinitionBindings) }
                $ctx.ExecuteQuery()

                foreach ($ra in $web.RoleAssignments) {
                    $claimName = Test-CGClaimLogin -LoginName $ra.Member.LoginName -Claims $claims
                    if (-not $claimName) { continue }
                    $roles = ($ra.RoleDefinitionBindings | ForEach-Object { $_.Name } | Where-Object { $_ -ne 'Limited Access' }) -join ', '
                    if (-not $roles) { continue }
                    $siteFindings.Add([pscustomobject]@{
                        Site = $siteUrl; Scope = 'Site'; Object = $web.Title; Claim = $claimName; Permission = $roles; Url = $web.Url
                    })
                }

                # --- List-level role assignments (optional) ---
                if ($IncludeLists) {
                    $lists = Get-PnPList -Includes HasUniqueRoleAssignments, RoleAssignments, Title, Hidden, DefaultViewUrl -Verbose:$false |
                        Where-Object { -not $_.Hidden -and $_.HasUniqueRoleAssignments }

                    foreach ($list in $lists) {
                        $ctx.Load($list.RoleAssignments)
                        $ctx.ExecuteQuery()
                        foreach ($ra in $list.RoleAssignments) { $ctx.Load($ra.Member); $ctx.Load($ra.RoleDefinitionBindings) }
                        $ctx.ExecuteQuery()

                        foreach ($ra in $list.RoleAssignments) {
                            $claimName = Test-CGClaimLogin -LoginName $ra.Member.LoginName -Claims $claims
                            if (-not $claimName) { continue }
                            $roles = ($ra.RoleDefinitionBindings | ForEach-Object { $_.Name } | Where-Object { $_ -ne 'Limited Access' }) -join ', '
                            if (-not $roles) { continue }
                            $siteFindings.Add([pscustomobject]@{
                                Site = $siteUrl; Scope = 'List'; Object = $list.Title; Claim = $claimName; Permission = $roles; Url = $list.DefaultViewUrl
                            })
                        }
                    }
                }

                foreach ($f in $siteFindings) { $results.Add($f) }
                break
            }
            catch {
                $msg = $_.Exception.Message
                if (($msg -match '429|throttl|Too Many Requests|503|Service Unavailable') -and $attempt -lt 4) {
                    $delay = [int](3 * [Math]::Pow(2, $attempt - 1))
                    Write-Warning ("Throttled on {0} (attempt {1}/3); retrying in {2}s..." -f $siteUrl, $attempt, $delay)
                    Start-Sleep -Seconds $delay
                    continue
                }
                Write-Warning "Skipped $siteUrl : $msg"
                $skippedSites.Add($siteUrl)
                break
            }
        }
    }

    if ($AllSites) { Write-Progress -Activity "Scanning for Everyone/EEEU access" -Completed }

    # Expose scan coverage so the orchestrator (and curious callers) can report blind spots.
    $script:CGCoverage = [pscustomobject]@{ Total = $total; Skipped = @($skippedSites) }

    # value-moment feedback nudge (once)
    Write-Host ""
    $line = "  {0} 'Everyone/EEEU' grant(s) found" -f $results.Count
    if ($total -gt 1) { $line += " across {0} site(s) scanned" -f ($total - $skippedSites.Count) }
    Write-Host ($line + ".") -ForegroundColor Yellow
    if ($skippedSites.Count -gt 0) {
        Write-Host ("  Coverage: {0} of {1} site(s) could not be read (see warnings) - results are partial." -f $skippedSites.Count, $total) -ForegroundColor DarkYellow
    }
    Write-Host "  Useful? Star: https://github.com/gvijaikumar9/CopilotGovernance  |  Feedback: Send-CopilotGovernanceFeedback" -ForegroundColor DarkCyan

    return $results
}
