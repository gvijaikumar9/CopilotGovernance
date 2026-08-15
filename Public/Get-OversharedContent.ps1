function Get-OversharedContent {
    <#
    .SYNOPSIS
        Finds content shared through Anonymous ("Anyone") and Organization-wide
        sharing links - the links that let Copilot surface files to people who were
        never explicitly given access.

    .DESCRIPTION
        Reads each site's hidden "SharingLinks.*" groups rather than walking every
        file, so it scales. Each sharing link SharePoint creates leaves one such
        group; the group title encodes the link kind (Anonymous*, Organization*,
        Flexible/Specific), and its membership is who the link was shared with.

        Anonymous links = highest risk (no sign-in). Organization links = anyone in
        the tenant. Specific/people links are normal and excluded unless
        -IncludeSpecific. Read-only.

        Complements SharingLinkAudit (which revokes/filters links); here the output
        feeds Invoke-CopilotReadinessAssessment.

    .PARAMETER Site
        A single site collection URL to scan.

    .PARAMETER AllSites
        Scan the whole tenant (admin connection + -ClientId). Skips the tenant root
        and system sites by default.

    .PARAMETER LinkType
        Which oversharing links to report: Anonymous, Organization, or All (both, default).

    .PARAMETER IncludeSpecific
        Also include people-specific ("Flexible") links (normally not oversharing).

    .PARAMETER IncludeRootSite
        Include the tenant root site during -AllSites (large; off by default).

    .PARAMETER ClientId
        Your PnP Entra app client id (needed to reconnect per-site during -AllSites).

    .EXAMPLE
        Get-OversharedContent -Site "https://contoso.sharepoint.com/sites/hr"

    .EXAMPLE
        Get-OversharedContent -AllSites -ClientId $cid -LinkType Anonymous |
            Export-Csv anon-links.csv -NoTypeInformation
    #>
    [CmdletBinding(DefaultParameterSetName = 'Site')]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory, ParameterSetName = 'Site', Position = 0)]
        [string]$Site,

        [Parameter(Mandatory, ParameterSetName = 'AllSites')]
        [switch]$AllSites,

        [ValidateSet('Anonymous', 'Organization', 'All')]
        [string]$LinkType = 'All',

        [switch]$IncludeSpecific,

        [switch]$IncludeRootSite,

        [string]$ClientId
    )

    $results = [System.Collections.Generic.List[object]]::new()
    $skippedSites = [System.Collections.Generic.List[string]]::new()  # coverage: sites we couldn't read

    # Which classes are we keeping?
    $keep = switch ($LinkType) {
        'Anonymous'    { @('Anonymous') }
        'Organization' { @('Organization') }
        default        { @('Anonymous', 'Organization') }
    }
    if ($IncludeSpecific) { $keep += 'Specific' }

    # Resolve sites to scan
    if ($AllSites) {
        if (-not $ClientId) { throw "-AllSites requires -ClientId to reconnect to each site." }
        Write-Verbose "Enumerating tenant sites..."
        $siteUrls = Get-PnPTenantSite -ErrorAction Stop -Verbose:$false |
            Where-Object {
                $_.Template -notmatch 'Redirect' -and
                $_.Template -notmatch 'SPSMSITEHOST' -and
                ($IncludeRootSite -or ([System.Uri]$_.Url).AbsolutePath -ne '/')
            } | Select-Object -ExpandProperty Url
    }
    else {
        $siteUrls = @($Site)
    }

    $total = @($siteUrls).Count
    $i = 0
    foreach ($siteUrl in $siteUrls) {
        $i++
        if ($AllSites) {
            Write-Progress -Activity "Scanning for oversharing links" -Status ("{0}/{1}  {2}" -f $i, $total, $siteUrl) -PercentComplete (($i / [Math]::Max($total, 1)) * 100)
            Write-Verbose ("[{0}/{1}] {2}" -f $i, $total, $siteUrl)
        }
        # Connect to the target site if a ClientId is given (so -Site "just works"
        # without a prior Connect); otherwise use the current ambient connection.
        if ($AllSites -or $ClientId) {
            try { Connect-PnPOnline -Url $siteUrl -Interactive -ClientId $ClientId -ErrorAction Stop -Verbose:$false }
            catch { Write-Warning "Could not connect to $siteUrl : $($_.Exception.Message)"; $skippedSites.Add($siteUrl); continue }
        }

        # Scan with bounded retry on transient throttling; accumulate per-site and
        # only merge on success so a retry never double-counts.
        $attempt = 0
        while ($true) {
            $attempt++
            $siteFindings = [System.Collections.Generic.List[object]]::new()
            try {
                $groups = Get-PnPGroup -Verbose:$false | Where-Object { $_.Title -like 'SharingLinks.*' }
                foreach ($g in $groups) {
                    $info = Get-CGLinkClass -Title $g.Title
                    if ($keep -notcontains $info.Class) { continue }

                    # Anonymous/Organization links are broad by nature (no explicit member
                    # list), so only pay for a membership call on people-specific links.
                    $sharedWith = 0
                    if ($info.Class -eq 'Specific') {
                        try { $sharedWith = @(Get-PnPGroupMember -Group $g -Verbose:$false | Where-Object { $_.LoginName }).Count }
                        catch { Write-Verbose "Could not count members for $($g.Title): $($_.Exception.Message)" }
                    }

                    $siteFindings.Add([pscustomobject]@{
                        Site            = $siteUrl
                        LinkClass       = $info.Class
                        LinkKind        = $info.Kind
                        SharedWithCount = $sharedWith
                        GroupTitle      = $g.Title
                    })
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

    if ($AllSites) { Write-Progress -Activity "Scanning for oversharing links" -Completed }

    # Expose scan coverage so the orchestrator (and curious callers) can report blind spots.
    $script:CGCoverage = [pscustomobject]@{ Total = $total; Skipped = @($skippedSites) }

    $anon = @($results | Where-Object { $_.LinkClass -eq 'Anonymous' }).Count
    $org  = @($results | Where-Object { $_.LinkClass -eq 'Organization' }).Count
    Write-Host ""
    Write-Host ("  {0} oversharing link(s): {1} anonymous, {2} organization-wide." -f $results.Count, $anon, $org) -ForegroundColor Yellow
    if ($skippedSites.Count -gt 0) {
        Write-Host ("  Coverage: {0} of {1} site(s) could not be read (see warnings) - results are partial." -f $skippedSites.Count, $total) -ForegroundColor DarkYellow
    }
    Write-Host "  Useful? Star: https://github.com/gvijaikumar9/CopilotGovernance  |  Feedback: Send-CopilotGovernanceFeedback" -ForegroundColor DarkCyan

    return $results
}
