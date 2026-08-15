function Invoke-CopilotReadinessAssessment {
    <#
    .SYNOPSIS
        Runs the full Copilot readiness assessment (Everyone/EEEU grants +
        oversharing links) and produces a branded HTML scorecard.

    .DESCRIPTION
        Composes Get-EveryoneAccess and Get-OversharedContent over a single site or
        the whole tenant, scores the exposure (0-100, higher = safer), writes a
        self-contained HTML scorecard, and returns a summary object. Read-only.

        Score = 100 - min(100, anonymousLinks*8 + everyoneGrants*4 + orgLinks*2),
        so anonymous ("Anyone") links weigh heaviest.

    .PARAMETER Site
        A single site collection URL to assess.

    .PARAMETER AllSites
        Assess the whole tenant (admin connection + -ClientId).

    .PARAMETER IncludeRootSite
        Include the tenant root site during -AllSites (large; off by default).

    .PARAMETER ClientId
        Your PnP Entra app client id (needed for -AllSites).

    .PARAMETER OutputHtml
        Path for the HTML scorecard (default .\CopilotReadiness.html).

    .PARAMETER Show
        Open the scorecard in the default browser when done.

    .EXAMPLE
        Invoke-CopilotReadinessAssessment -AllSites -ClientId $cid -Show
    #>
    [CmdletBinding(DefaultParameterSetName = 'Site')]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory, ParameterSetName = 'Site', Position = 0)]
        [string]$Site,

        [Parameter(Mandatory, ParameterSetName = 'AllSites')]
        [switch]$AllSites,

        [switch]$IncludeRootSite,

        [string]$ClientId,

        [string]$OutputHtml = (Join-Path (Get-Location) 'CopilotReadiness.html'),

        [switch]$Show
    )

    if ($AllSites -and -not $ClientId) { throw "-AllSites requires -ClientId." }

    Write-Host "Assessing Everyone/EEEU grants..." -ForegroundColor Cyan
    $everyone = if ($AllSites) {
        Get-EveryoneAccess -AllSites -ClientId $ClientId -IncludeRootSite:$IncludeRootSite
    } else {
        Get-EveryoneAccess -Site $Site
    }
    $covEveryone = $script:CGCoverage

    Write-Host "Assessing oversharing links..." -ForegroundColor Cyan
    $shares = if ($AllSites) {
        Get-OversharedContent -AllSites -ClientId $ClientId -IncludeRootSite:$IncludeRootSite
    } else {
        Get-OversharedContent -Site $Site
    }
    $covShares = $script:CGCoverage

    # --- score ---
    $anon = @($shares   | Where-Object { $_.LinkClass -eq 'Anonymous' }).Count
    $org  = @($shares   | Where-Object { $_.LinkClass -eq 'Organization' }).Count
    $eeeu = @($everyone).Count
    $sc    = Get-CGReadinessScore -AnonymousLinks $anon -EveryoneGrants $eeeu -OrganizationLinks $org
    $score = $sc.Score
    $band  = $sc.Band

    $sitesAtRisk = @(@($everyone.Site) + @($shares.Site) | Where-Object { $_ } | Select-Object -Unique).Count

    # Coverage: union of sites either scan could not read (blind spots).
    $skippedSites = @(@($covEveryone.Skipped) + @($covShares.Skipped) | Where-Object { $_ } | Select-Object -Unique)
    $totalSites   = [Math]::Max([int]$covEveryone.Total, [int]$covShares.Total)
    $scannedSites = $totalSites - $skippedSites.Count

    $summary = @{
        Score        = $score
        Band         = $band
        Anon         = $anon
        Org          = $org
        Eeeu         = $eeeu
        SitesAtRisk  = $sitesAtRisk
        Total        = $totalSites
        Scanned      = $scannedSites
        Skipped      = $skippedSites.Count
        SkippedSites = $skippedSites
        ScopeLabel   = if ($AllSites) { 'Whole tenant' } else { $Site }
        Generated    = (Get-Date).ToString('yyyy-MM-dd HH:mm')
    }

    New-CGScorecardHtml -Everyone $everyone -Shares $shares -Summary $summary -Path $OutputHtml
    Write-Host ""
    Write-Host ("  Readiness score: {0}/100 ({1})" -f $score, $band) -ForegroundColor $(if ($score -ge 80) { 'Green' } elseif ($score -ge 50) { 'Yellow' } else { 'Red' })
    Write-Host ("  Scorecard: {0}" -f $OutputHtml) -ForegroundColor Cyan
    if ($skippedSites.Count -gt 0) {
        Write-Host ("  Coverage: scanned {0} of {1} sites; {2} could not be read - the score may understate exposure." -f $scannedSites, $totalSites, $skippedSites.Count) -ForegroundColor DarkYellow
    }

    if ($Show) { Invoke-Item $OutputHtml }

    [pscustomobject]@{
        Score             = $score
        Band              = $band
        AnonymousLinks    = $anon
        OrganizationLinks = $org
        EveryoneGrants    = $eeeu
        SitesAtRisk       = $sitesAtRisk
        SitesScanned      = $scannedSites
        SitesSkipped      = $skippedSites.Count
        SkippedSites      = $skippedSites
        Report            = $OutputHtml
        EveryoneAccess    = $everyone
        OversharedContent = $shares
    }
}
