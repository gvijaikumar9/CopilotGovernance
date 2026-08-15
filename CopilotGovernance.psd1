@{
    RootModule        = 'CopilotGovernance.psm1'
    ModuleVersion     = '0.3.0'
    GUID              = 'b7e1c2a4-9f3d-4c8e-8a2b-1d6f0e5c7a90'
    Author            = 'G Vijai Kumar'
    CompanyName       = 'Five Number'
    Copyright         = '(c) 2026 G Vijai Kumar. MIT License.'
    Description       = 'See what Microsoft 365 Copilot will see - before it does. A free governance toolkit that surfaces the oversharing (Everyone/EEEU access, anonymous links, guest reach, unlabeled-but-exposed content) that Copilot amplifies. Read-only. Requires PnP.PowerShell.'
    PowerShellVersion = '7.2'

    RequiredModules   = @(
        @{ ModuleName = 'PnP.PowerShell'; ModuleVersion = '2.2.0' }
    )

    FunctionsToExport = @(
        'Connect-CopilotGovernance',
        'Get-EveryoneAccess',
        'Get-OversharedContent',
        'Get-GuestExposure',
        'Invoke-CopilotReadinessAssessment',
        'Send-CopilotGovernanceFeedback'
    )
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()

    PrivateData = @{
        PSData = @{
            Tags         = @('Copilot','Governance','Oversharing','SharePoint','Microsoft365','M365','Security','PnP','DataAccessGovernance','Purview')
            LicenseUri   = 'https://github.com/gvijaikumar9/CopilotGovernance/blob/main/LICENSE'
            ProjectUri   = 'https://github.com/gvijaikumar9/CopilotGovernance'
            ReleaseNotes = 'v0.3.0 - Get-GuestExposure (inventories guest/external users and flags stale ones via Microsoft Graph; needs User.Read.All, and AuditLog.Read.All for sign-in based staleness). v0.2.0 - Get-OversharedContent + Invoke-CopilotReadinessAssessment (HTML Copilot Readiness Scorecard). v0.1.0 - Get-EveryoneAccess.'
        }
    }
}
