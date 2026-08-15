function Send-CopilotGovernanceFeedback {
    <#
    .SYNOPSIS
        Opens the feedback form so you can tell me how you're using the toolkit.

    .DESCRIPTION
        PowerShell Gallery is anonymous - no reviews, no way to reach the author.
        This opens a short browser form (30 seconds) so real users can send named,
        consented feedback. It powers improvements and, with your consent, a public
        testimonial. Nothing is collected unless you submit the form yourself.

    .EXAMPLE
        Send-CopilotGovernanceFeedback
    #>
    [CmdletBinding()]
    param(
        [string]$Version
    )

    if (-not $Version) {
        $mod = Get-Module -Name CopilotGovernance | Select-Object -First 1
        if ($mod) { $Version = $mod.Version.ToString() }
    }

    $url = "https://tools.fivenumber.com/feedback/?tool=CopilotGovernance&ver=$Version"
    Write-Host "Opening the feedback form in your browser:" -ForegroundColor Cyan
    Write-Host "  $url"
    Start-Process $url
}
