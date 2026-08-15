function Connect-CopilotGovernance {
    <#
    .SYNOPSIS
        Connects to SharePoint Online for the Copilot Governance cmdlets.

    .DESCRIPTION
        A thin wrapper over Connect-PnPOnline so every cmdlet in the toolkit shares
        one authentication entry point. Read-only usage - the toolkit never changes
        anything unless you explicitly ask a future -Remediate switch to.

        PnP.PowerShell 3.x requires your own Entra app registration client id.

    .PARAMETER Url
        The site or tenant-admin URL to connect to
        (e.g. https://contoso-admin.sharepoint.com for -AllSites scans).

    .PARAMETER ClientId
        Your PnP Entra app registration (client) id.

    .EXAMPLE
        Connect-CopilotGovernance -Url "https://contoso-admin.sharepoint.com" -ClientId "<guid>"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Url,
        [Parameter(Mandatory)][string]$ClientId
    )

    if (-not (Get-Module -ListAvailable -Name PnP.PowerShell)) {
        throw "PnP.PowerShell is required. Run: Install-Module PnP.PowerShell -Scope CurrentUser"
    }

    Connect-PnPOnline -Url $Url -Interactive -ClientId $ClientId
    Write-Verbose "Connected to $Url"
}
