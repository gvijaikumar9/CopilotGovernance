# Builds the branded Copilot Readiness Scorecard HTML from the gathered findings.
# Self-contained (inline CSS) so the file can be shared or screenshotted as-is.

function New-CGScorecardHtml {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [object[]]$Everyone,
        [object[]]$Shares,
        [hashtable]$Summary,
        [Parameter(Mandatory)][string]$Path
    )

    # HTML-encode any value that came from SharePoint (site/library titles can
    # legitimately contain & < > and would otherwise break the markup).
    function Enc([object]$v) { [System.Net.WebUtility]::HtmlEncode([string]$v) }

    $accentBand =
        if ($Summary.Score -ge 80) { '#107c10' }      # low risk - green
        elseif ($Summary.Score -ge 50) { '#f7630c' }  # attention - orange
        else { '#d13438' }                             # high risk - red

    # per-site rollup
    $siteNames = @($Everyone.Site + $Shares.Site | Where-Object { $_ } | Select-Object -Unique | Sort-Object)
    $siteRows = foreach ($s in $siteNames) {
        $se = @($Everyone | Where-Object { $_.Site -eq $s }).Count
        $sa = @($Shares   | Where-Object { $_.Site -eq $s -and $_.LinkClass -eq 'Anonymous' }).Count
        $so = @($Shares   | Where-Object { $_.Site -eq $s -and $_.LinkClass -eq 'Organization' }).Count
        $risk = if ($sa -gt 0) { 'High' } elseif ($se -gt 0 -or $so -gt 0) { 'Medium' } else { 'Low' }
        "<tr><td class='u'>$(Enc $s)</td><td class='n'>$se</td><td class='n'>$sa</td><td class='n'>$so</td><td><span class='pill $($risk.ToLower())'>$risk</span></td></tr>"
    }
    if (-not $siteRows) { $siteRows = "<tr><td colspan='5' class='muted'>No sites with exposure found.</td></tr>" }

    $eeeuRows = foreach ($e in $Everyone) {
        "<tr><td class='u'>$(Enc $e.Site)</td><td>$(Enc $e.Claim)</td><td>$(Enc $e.Permission)</td><td>$(Enc $e.Scope)</td></tr>"
    }
    if (-not $eeeuRows) { $eeeuRows = "<tr><td colspan='4' class='muted'>None.</td></tr>" }

    $linkRows = foreach ($l in ($Shares | Sort-Object LinkClass, Site)) {
        "<tr><td class='u'>$(Enc $l.Site)</td><td><span class='pill $($l.LinkClass.ToLower())'>$(Enc $l.LinkClass)</span></td><td class='n'>$($l.SharedWithCount)</td><td class='mono'>$(Enc $l.LinkKind)</td></tr>"
    }
    if (-not $linkRows) { $linkRows = "<tr><td colspan='4' class='muted'>None.</td></tr>" }

    # Coverage strip - only when some sites could not be read (blind spots).
    $coverageWarn = ''
    if ($Summary.Skipped -and [int]$Summary.Skipped -gt 0) {
        $list = (@($Summary.SkippedSites) | ForEach-Object { Enc $_ }) -join ', '
        $coverageWarn = "<div class=""warn""><strong>Partial coverage.</strong> $([int]$Summary.Skipped) site(s) could not be read and are <em>not</em> reflected in the score: $list</div>"
    }
    $coverageSub = if ($Summary.Total) { " &middot; scanned $($Summary.Scanned) of $($Summary.Total) sites" } else { '' }

    $html = @"
<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>Copilot Readiness Scorecard</title>
<style>
  :root{--ink:#242424;--muted:#605e5c;--line:#e1dfdd;--card:#fff;--bg:#faf9f8;--accent:#0f6cbd;}
  *{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--ink);font-family:'Segoe UI',system-ui,Arial,sans-serif;line-height:1.45}
  .wrap{max-width:1080px;margin:0 auto;padding:28px 22px 60px}
  header{display:flex;align-items:center;gap:18px;flex-wrap:wrap;margin-bottom:6px}
  h1{font-size:24px;margin:0;font-weight:600;letter-spacing:-.01em}
  .sub{color:var(--muted);font-size:13.5px;margin:2px 0 0}
  .score{margin-left:auto;text-align:center;background:var(--card);border:1px solid var(--line);border-radius:14px;padding:14px 22px;min-width:150px}
  .score .num{font-size:40px;font-weight:700;line-height:1;color:$accentBand}
  .score .band{font-size:12.5px;font-weight:700;text-transform:uppercase;letter-spacing:.06em;color:$accentBand;margin-top:4px}
  .score .lbl{font-size:11px;color:var(--muted);margin-top:6px}
  .tiles{display:grid;grid-template-columns:repeat(4,1fr);gap:14px;margin:22px 0}
  @media(max-width:680px){.tiles{grid-template-columns:repeat(2,1fr)}}
  .tile{background:var(--card);border:1px solid var(--line);border-radius:12px;padding:16px 18px}
  .tile .v{font-size:28px;font-weight:700}.tile .k{color:var(--muted);font-size:12.5px;margin-top:2px}
  .tile.crit .v{color:#d13438}.tile.warn .v{color:#f7630c}.tile.info .v{color:var(--accent)}
  h2{font-size:16px;margin:26px 0 10px;font-weight:600}
  table{width:100%;border-collapse:collapse;background:var(--card);border:1px solid var(--line);border-radius:12px;overflow:hidden;font-size:13px}
  th,td{text-align:left;padding:9px 12px;border-bottom:1px solid var(--line);vertical-align:top}
  th{background:#f3f2f1;font-weight:600;font-size:12px;text-transform:uppercase;letter-spacing:.03em;color:var(--muted)}
  tr:last-child td{border-bottom:0}
  td.n{text-align:right;font-variant-numeric:tabular-nums}
  td.u{word-break:break-all;max-width:420px}.mono{font-family:Consolas,monospace;font-size:11.5px;color:var(--muted)}
  .muted{color:var(--muted)}
  .pill{display:inline-block;font-size:11px;font-weight:700;padding:2px 9px;border-radius:100px}
  .pill.high,.pill.anonymous{background:#fdf3f4;color:#d13438}
  .pill.medium,.pill.organization{background:#fdf1e9;color:#b3560b}
  .pill.low,.pill.specific{background:#dff6dd;color:#107c10}
  footer{margin-top:30px;color:var(--muted);font-size:12.5px;border-top:1px solid var(--line);padding-top:16px}
  a{color:var(--accent);text-decoration:none}a:hover{text-decoration:underline}
  .note{background:#eff6fc;border:1px solid #cfe4f7;border-radius:10px;padding:12px 14px;font-size:13px;margin:14px 0}
  .warn{background:#fdf1e9;border:1px solid #f6d9c2;border-radius:10px;padding:12px 14px;font-size:13px;margin:14px 0;color:#8a4b0b;word-break:break-all}
</style></head>
<body><div class="wrap">
  <header>
    <div>
      <h1>Copilot Readiness Scorecard</h1>
      <p class="sub">$(Enc $Summary.ScopeLabel)$coverageSub &middot; generated $($Summary.Generated)</p>
    </div>
    <div class="score"><div class="num">$($Summary.Score)</div><div class="band">$($Summary.Band)</div><div class="lbl">readiness / 100</div></div>
  </header>

  <div class="note"><strong>What this measures.</strong> Microsoft 365 Copilot can surface anything a user can already reach. This scorecard flags the broad access that makes that a risk &mdash; Everyone/EEEU grants and Anonymous / Organization-wide sharing links &mdash; so you can fix it before turning Copilot on. Read-only; nothing was changed.</div>
  $coverageWarn

  <div class="tiles">
    <div class="tile crit"><div class="v">$($Summary.Anon)</div><div class="k">Anonymous links</div></div>
    <div class="tile warn"><div class="v">$($Summary.Org)</div><div class="k">Organization-wide links</div></div>
    <div class="tile warn"><div class="v">$($Summary.Eeeu)</div><div class="k">Everyone / EEEU grants</div></div>
    <div class="tile info"><div class="v">$($Summary.SitesAtRisk)</div><div class="k">Sites with exposure</div></div>
  </div>

  <h2>By site</h2>
  <table><thead><tr><th>Site</th><th>EEEU/Everyone</th><th>Anon links</th><th>Org links</th><th>Risk</th></tr></thead>
  <tbody>
$($siteRows -join "`n")
  </tbody></table>

  <h2>Everyone / Everyone-Except-External-Users grants</h2>
  <table><thead><tr><th>Site</th><th>Claim</th><th>Permission</th><th>Scope</th></tr></thead>
  <tbody>
$($eeeuRows -join "`n")
  </tbody></table>

  <h2>Oversharing links</h2>
  <table><thead><tr><th>Site</th><th>Type</th><th>Shared with</th><th>Kind</th></tr></thead>
  <tbody>
$($linkRows -join "`n")
  </tbody></table>

  <footer>
    Generated by <strong>CopilotGovernance</strong> &mdash; a free, read-only M365 oversharing toolkit.
    &nbsp;&#9733; <a href="https://github.com/gvijaikumar9/CopilotGovernance">Star on GitHub</a>
    &nbsp;&middot;&nbsp; run <code>Send-CopilotGovernanceFeedback</code> to tell me how you used it.
  </footer>
</div></body></html>
"@

    if ($PSCmdlet.ShouldProcess($Path, 'Write Copilot Readiness Scorecard')) {
        Set-Content -Path $Path -Value $html -Encoding UTF8
    }
}
