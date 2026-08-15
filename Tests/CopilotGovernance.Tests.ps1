#Requires -Modules Pester

BeforeAll {
    $root = Split-Path $PSScriptRoot -Parent
    Import-Module (Join-Path $root 'CopilotGovernance.psd1') -Force
}

Describe 'Test-CGClaimLogin (claim matching)' {
    It 'matches Everyone by exact login' {
        InModuleScope CopilotGovernance {
            Test-CGClaimLogin -LoginName 'c:0(.s|true' -Claims (Get-CGClaim) | Should -Be 'Everyone'
        }
    }
    It 'matches EEEU by the tenant-independent fragment' {
        InModuleScope CopilotGovernance {
            Test-CGClaimLogin -LoginName 'c:0-.f|rolemanager|spo-grid-all-users/abc-123' -Claims (Get-CGClaim) |
                Should -Be 'Everyone except external users'
        }
    }
    It 'returns nothing for a normal user login' {
        InModuleScope CopilotGovernance {
            Test-CGClaimLogin -LoginName 'i:0#.f|membership|jo@contoso.com' -Claims (Get-CGClaim) | Should -BeNullOrEmpty
        }
    }
    It 'returns nothing for an empty login' {
        InModuleScope CopilotGovernance {
            Test-CGClaimLogin -LoginName '' -Claims (Get-CGClaim) | Should -BeNullOrEmpty
        }
    }
    It 'ClaimType Everyone does not match EEEU' {
        InModuleScope CopilotGovernance {
            Test-CGClaimLogin -LoginName 'c:0-.f|rolemanager|spo-grid-all-users/x' -Claims (Get-CGClaim -ClaimType Everyone) |
                Should -BeNullOrEmpty
        }
    }
}

Describe 'Get-CGLinkClass (SharingLinks classification)' {
    It 'classifies AnonymousEdit as Anonymous' {
        InModuleScope CopilotGovernance { (Get-CGLinkClass -Title 'SharingLinks.a.AnonymousEdit.b').Class | Should -Be 'Anonymous' }
    }
    It 'classifies OrganizationView as Organization' {
        InModuleScope CopilotGovernance { (Get-CGLinkClass -Title 'SharingLinks.a.OrganizationView.b').Class | Should -Be 'Organization' }
    }
    It 'classifies Flexible as Specific' {
        InModuleScope CopilotGovernance { (Get-CGLinkClass -Title 'SharingLinks.a.Flexible.b').Class | Should -Be 'Specific' }
    }
    It 'preserves the raw kind fragment' {
        InModuleScope CopilotGovernance { (Get-CGLinkClass -Title 'SharingLinks.a.OrganizationEdit.b').Kind | Should -Be 'OrganizationEdit' }
    }
    It 'handles a malformed title as Other' {
        InModuleScope CopilotGovernance { (Get-CGLinkClass -Title 'SharingLinks.only').Class | Should -Be 'Other' }
    }
}

Describe 'Get-CGReadinessScore (scoring formula)' {
    It 'is 100 for a clean tenant' {
        InModuleScope CopilotGovernance { (Get-CGReadinessScore).Score | Should -Be 100 }
    }
    It 'weights anonymous > everyone > organization' {
        InModuleScope CopilotGovernance {
            (Get-CGReadinessScore -AnonymousLinks 1).Score    | Should -Be 92
            (Get-CGReadinessScore -EveryoneGrants 1).Score    | Should -Be 96
            (Get-CGReadinessScore -OrganizationLinks 1).Score | Should -Be 98
        }
    }
    It 'reproduces the validated wayll case (3 EEEU + 1 org = 86)' {
        InModuleScope CopilotGovernance { (Get-CGReadinessScore -EveryoneGrants 3 -OrganizationLinks 1).Score | Should -Be 86 }
    }
    It 'floors at 0' {
        InModuleScope CopilotGovernance { (Get-CGReadinessScore -AnonymousLinks 100).Score | Should -Be 0 }
    }
    It 'assigns the right risk bands' {
        InModuleScope CopilotGovernance {
            (Get-CGReadinessScore).Band                     | Should -Be 'Low risk'         # 100
            (Get-CGReadinessScore -EveryoneGrants 10).Band  | Should -Be 'Needs attention'  # 60
            (Get-CGReadinessScore -AnonymousLinks 8).Band   | Should -Be 'High risk'        # 36
        }
    }
}

Describe 'New-CGScorecardHtml (report rendering)' {
    It 'writes a valid HTML file and HTML-encodes special characters' {
        InModuleScope CopilotGovernance {
            $tmp = Join-Path ([IO.Path]::GetTempPath()) 'cg-test-scorecard.html'
            $e   = @([pscustomobject]@{ Site = 'https://x/sites/r&d'; Scope = 'Site'; Object = 'x'; Claim = 'Everyone'; Permission = 'Read'; Url = 'u' })
            $sm  = @{ Score = 96; Band = 'Low risk'; Anon = 0; Org = 0; Eeeu = 1; SitesAtRisk = 1; ScopeLabel = 'https://x/sites/r&d'; Generated = 't' }
            New-CGScorecardHtml -Everyone $e -Shares @() -Summary $sm -Path $tmp
            Test-Path $tmp | Should -BeTrue
            $html = Get-Content $tmp -Raw
            $html | Should -Match 'r&amp;d'
            $html | Should -Match '</html>'
            Remove-Item $tmp -ErrorAction SilentlyContinue
        }
    }
    It 'renders a partial-coverage warning when sites were skipped' {
        InModuleScope CopilotGovernance {
            $tmp = Join-Path ([IO.Path]::GetTempPath()) 'cg-test-coverage.html'
            $sm  = @{ Score = 100; Band = 'Low risk'; Anon = 0; Org = 0; Eeeu = 0; SitesAtRisk = 0
                     Total = 40; Scanned = 39; Skipped = 1; SkippedSites = @('https://x/sites/locked')
                     ScopeLabel = 'Whole tenant'; Generated = 't' }
            New-CGScorecardHtml -Everyone @() -Shares @() -Summary $sm -Path $tmp
            $html = Get-Content $tmp -Raw
            $html | Should -Match 'Partial coverage'
            $html | Should -Match 'scanned 39 of 40 sites'
            $html | Should -Match 'sites/locked'
            Remove-Item $tmp -ErrorAction SilentlyContinue
        }
    }
    It 'omits the coverage strip when nothing was skipped' {
        InModuleScope CopilotGovernance {
            $tmp = Join-Path ([IO.Path]::GetTempPath()) 'cg-test-nocov.html'
            $sm  = @{ Score = 100; Band = 'Low risk'; Anon = 0; Org = 0; Eeeu = 0; SitesAtRisk = 0
                     ScopeLabel = 'Whole tenant'; Generated = 't' }
            New-CGScorecardHtml -Everyone @() -Shares @() -Summary $sm -Path $tmp
            (Get-Content $tmp -Raw) | Should -Not -Match 'Partial coverage'
            Remove-Item $tmp -ErrorAction SilentlyContinue
        }
    }
}
