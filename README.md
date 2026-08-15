# CopilotGovernance

**See what Microsoft 365 Copilot will see — before it does.**

M365 Copilot surfaces anything a user can *already* access. So your tenant's
existing oversharing — broad permissions and stray links nobody noticed — becomes a
data-exposure problem the moment Copilot is switched on. Microsoft's own
data-access-governance reports need the **paid** SharePoint Advanced Management
add-on. **CopilotGovernance is the free, scriptable way to find that exposure first.**

Read-only. It reports; it never changes anything.

## Install

```powershell
Install-Module CopilotGovernance -Scope CurrentUser
```

Requires **PowerShell 7.2+** and **PnP.PowerShell** (installed automatically), plus
your own PnP Entra app registration client id.

## Quick start

```powershell
$cid = "<your-pnp-app-client-id>"

# One site
Connect-CopilotGovernance -Url "https://contoso.sharepoint.com/sites/hr" -ClientId $cid
Get-EveryoneAccess -Site "https://contoso.sharepoint.com/sites/hr" -IncludeLists

# Whole tenant
Connect-CopilotGovernance -Url "https://contoso-admin.sharepoint.com" -ClientId $cid
Get-EveryoneAccess -AllSites -ClientId $cid |
    Export-Csv everyone-access.csv -NoTypeInformation

# Full assessment → HTML scorecard
Invoke-CopilotReadinessAssessment -AllSites -ClientId $cid -Show
```

## What's in the toolkit

| Cmdlet | Status | What it does |
|---|---|---|
| **`Get-EveryoneAccess`** | ✅ | Every place the `Everyone` / `Everyone Except External Users` (EEEU) claim grants access — the #1 oversharing culprit. |
| **`Get-OversharedContent`** | ✅ | Anonymous ("Anyone") and Organization-wide sharing links, found via the scalable SharingLinks-groups method (no per-file walking). |
| **`Invoke-CopilotReadinessAssessment`** | ✅ | Runs both scans → a scored, branded HTML **Copilot Readiness Scorecard**. |
| `Get-GuestExposure` | planned | Guests + exactly what each can reach; stale guests. |
| `Get-SensitivityLabelGap` | planned | Sensitive content that's unlabeled **and** overshared — the true Copilot risk. |
| `Get-CopilotAgentInventory` | planned | Declarative / Copilot Studio agents, owners, knowledge sources. |

## `Get-EveryoneAccess`

| Parameter | Description |
|---|---|
| `-Site <url>` | Scan a single site collection. |
| `-AllSites` | Scan the whole tenant (admin connection + `-ClientId`). Skips the tenant **root** site and system sites by default. |
| `-IncludeRootSite` | Also scan the tenant root (`/`) during `-AllSites` (large; off by default). |
| `-ClaimType` | `Everyone`, `EveryoneExceptExternal`, or `Both` (default). |
| `-IncludeLists` | Also inspect lists/libraries with unique permissions (slower). |

Output objects: `Site, Scope, Object, Claim, Permission, Url` — pipe to
`Export-Csv`, `Format-Table`, or `Where-Object` as usual.

## `Get-OversharedContent`

Finds **Anonymous ("Anyone")** and **Organization-wide** sharing links by reading each
site's hidden `SharingLinks.*` groups instead of walking every file, so it scales.

| Parameter | Description |
|---|---|
| `-Site <url>` / `-AllSites` | One site, or the whole tenant (`-ClientId` required for `-AllSites`). |
| `-LinkType` | `Anonymous`, `Organization`, or `All` (both, default). |
| `-IncludeSpecific` | Also include people-specific ("Flexible") links (normally not oversharing). |
| `-IncludeRootSite` | Include the tenant root during `-AllSites`. |

Output: `Site, LinkClass, LinkKind, SharedWithCount, GroupTitle`.

## `Invoke-CopilotReadinessAssessment`

Runs both scans, scores the exposure, and writes a self-contained HTML scorecard.

| Parameter | Description |
|---|---|
| `-Site <url>` / `-AllSites` | Assess one site or the whole tenant. |
| `-OutputHtml <path>` | Scorecard path (default `.\CopilotReadiness.html`). |
| `-Show` | Open the scorecard in the browser when done. |

**Score** = `100 − min(100, anonymousLinks×8 + everyoneGrants×4 + orgLinks×2)` — higher is
safer; anonymous links weigh heaviest. Returns a summary object plus the full findings.

## Scope & limitations (v0.2)

Honest about what it does and doesn't cover yet:

- Scans the **root web of each site collection** and (with `-IncludeLists`) its
  lists/libraries. **Sub-webs** with unique permissions are not walked yet — planned.
- `Get-OversharedContent` finds links via the **SharingLinks groups**; it reports the
  link and the item's document id, not the resolved file path (resolution is expensive
  at tenant scale) — planned as an opt-in `-ResolveUrl`.
- **Link classification** reads the link *kind* from the SharingLinks group name
  (`Anonymous*`, `Organization*`, `Flexible`). On tenants using the newer unified
  sharing experience, some org/anonymous links are created as **`Flexible`** with the
  audience stored in link settings rather than the name; those classify as *Specific*
  and are excluded by default, so the tool can **under-count** exposure on such tenants.
  Use **`-IncludeSpecific`** to review every link. Scope-aware inspection is planned.
- **Coverage is never silent.** Sites the app can't read are skipped with a warning, and
  the number of unreadable sites is shown in the console output *and* the scorecard, so a
  partial scan is always visible.
- Read-only. Transient throttling (HTTP 429/503) is retried with backoff; a site that
  still fails after retries is skipped (and counted, above) rather than aborting the run.
- App/least-privilege guidance: your PnP Entra app needs delegated
  `AllSites.FullControl` (or equivalent read on every site) to enumerate permissions.

## Feedback

PowerShell Gallery has no reviews, so if this helped:

- ⭐ **Star** the repo — it's how others find it.
- 💬 Run **`Send-CopilotGovernanceFeedback`** — a 30-second form (named + consented; nothing is sent unless you submit it).
- 🐞 Open an **Issue** or start a **Discussion** here on GitHub.

## License

[MIT](LICENSE) © 2026 G Vijai Kumar
