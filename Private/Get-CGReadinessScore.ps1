# Computes the Copilot readiness score from the exposure counts.
# Score = 100 - min(100, anonymous*8 + everyone*4 + organization*2); higher = safer.
# Anonymous ("Anyone") links weigh heaviest because they need no sign-in at all.

function Get-CGReadinessScore {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [int]$AnonymousLinks    = 0,
        [int]$EveryoneGrants    = 0,
        [int]$OrganizationLinks = 0
    )

    $penalty = [Math]::Min(100, ($AnonymousLinks * 8) + ($EveryoneGrants * 4) + ($OrganizationLinks * 2))
    $score   = 100 - $penalty
    $band    = if ($score -ge 80) { 'Low risk' } elseif ($score -ge 50) { 'Needs attention' } else { 'High risk' }

    [pscustomobject]@{ Score = $score; Band = $band; Penalty = $penalty }
}
