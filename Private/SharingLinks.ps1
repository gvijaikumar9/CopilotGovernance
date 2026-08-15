# Classifies a SharePoint "SharingLinks.*" group title into a link class.
#
# Title format:  SharingLinks.{documentUniqueId}.{LinkKind}.{sharingId}
# LinkKind examples: AnonymousView, AnonymousEdit, OrganizationView, OrganizationEdit,
#                    Flexible (people-specific). We match on the kind fragment so new
#                    view/edit variants still classify correctly.

function Get-CGLinkClass {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)][string]$Title
    )

    $parts = $Title -split '\.'
    $kind  = if ($parts.Count -ge 3) { $parts[2] } else { 'Unknown' }

    switch -Wildcard ($kind) {
        '*Anonymous*'    { return @{ Class = 'Anonymous';    Kind = $kind } }
        '*Organization*' { return @{ Class = 'Organization'; Kind = $kind } }
        'Flexible'       { return @{ Class = 'Specific';     Kind = $kind } }
        default          { return @{ Class = 'Other';        Kind = $kind } }
    }
}
