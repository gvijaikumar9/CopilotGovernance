# Changelog

## 0.2.0
- `Get-OversharedContent` — finds Anonymous ("Anyone") and Organization-wide sharing
  links via the scalable SharingLinks-groups method (no per-file walking).
- `Invoke-CopilotReadinessAssessment` — composes the scans, scores exposure (0–100),
  and writes a branded, self-contained HTML **Copilot Readiness Scorecard**.
- `Get-EveryoneAccess` — `-AllSites` hardened (skips the slow tenant root + system
  sites, per-site progress, resilient to unauthorized sites) and quieter `-Verbose`.
- **Coverage reporting** — unreadable sites are counted and surfaced in the console and
  the scorecard, so a partial scan is never mistaken for a clean tenant.
- Production hardening: transient-throttling retry with backoff (no double-counting),
  HTML-encoded reports, throttle-friendly member lookups, `[OutputType]`, and a
  Pester test suite. `-Site` now self-connects when given `-ClientId`.
- Known limitation documented: `Flexible`-kind links can under-count on tenants using
  the unified sharing experience — use `-IncludeSpecific` to review all links.

## 0.1.0
- First release.
- `Get-EveryoneAccess` — finds Everyone / Everyone-Except-External-Users grants at
  site and (optionally) list level, for a single site or the whole tenant.
- `Connect-CopilotGovernance` — shared auth wrapper over PnP.PowerShell.
- `Send-CopilotGovernanceFeedback` — opens the feedback form.
