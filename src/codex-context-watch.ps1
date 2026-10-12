<#
.SYNOPSIS
    Live dashboard that keeps refreshing Codex token stats in the current terminal.

.DESCRIPTION
    Polls the Codex session rollout file every N seconds and redraws:
      - tokens currently in context vs context window size
      - conversation totals: cached vs non-cached input, output

    By default it follows the most recently updated session, so it keeps
    pointing at your active conversation as you work. Press Ctrl+C to stop.

    Run this in a normal terminal window, not the Codex TUI's built-in shell:
    the live redraw (Clear-Host) needs a real console. When stdout is
    redirected, it appends timestamped frames instead of clearing the screen.

.PARAMETER IntervalSeconds
    Refresh interval. Default 5.

.PARAMETER SessionId
    Follow a specific session id instead of the most recent one.

.PARAMETER CodexHome
    Override the Codex home directory.

.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File .\codex-context-watch.ps1
#>
[CmdletBinding()]
param(
    [int]$IntervalSeconds = 5,
    [string]$SessionId,
    [string]$CodexHome
)

$ErrorActionPreference = 'Stop'
if ($IntervalSeconds -lt 1) { $IntervalSeconds = 1 }

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$statsScript = Join-Path $scriptDir 'codex-context-stats.ps1'
if (-not (Test-Path $statsScript)) { throw "codex-context-stats.ps1 not found next to this script: $statsScript" }

$title = 'Codex context stats (live)  -  Ctrl+C to stop'
$redirected = [Console]::IsOutputRedirected

function Format-Compact {
    param([long]$Value)
    if ($null -eq $Value) { return '?' }
    $abs = [Math]::Abs([long]$Value)
    if ($abs -ge 1000000) { return ('{0:N1}M' -f ($Value / 1000000)) }
    if ($abs -ge 1000)    { return ('{0:N1}k' -f ($Value / 1000)) }
    return [string]$Value
}

function Invoke-Stats {
    param([string]$Fmt)
    $params = @{ Format = $Fmt }
    if ($SessionId) { $params['SessionId'] = $SessionId }
    if ($CodexHome) { $params['CodexHome'] = $CodexHome }
    return (& $statsScript @params 2>&1 | Out-String)
}

while ($true) {
    $stats = $null
    $body = ''
    try {
        $statsJson = (Invoke-Stats -Fmt 'json').Trim()
        if ($statsJson) { $stats = $statsJson | ConvertFrom-Json }
        $body = Invoke-Stats -Fmt 'table'
    }
    catch {
        $body = 'Error: ' + $_.Exception.Message
    }

    $shortId = if ($stats -and $stats.SessionId) { $stats.SessionId.Substring(0, 8) } else { '?' }
    if ($stats -and $stats.LastUpdatedUtc) {
        $age = [DateTimeOffset]::UtcNow - [DateTimeOffset]::Parse([string]$stats.LastUpdatedUtc)
        $ageTxt = 'data {0:N0} s old' -f $age.TotalSeconds
    }
    else { $ageTxt = 'no usage data yet' }
    $banner = "$title  |  refresh " + (Get-Date).ToString('yyyy-MM-dd HH:mm:ss') + "  |  session $shortId  |  $ageTxt"

    if ($redirected) { Write-Host ('=' * 78) } else { Clear-Host }
    Write-Host $banner -ForegroundColor DarkGray
    if ($stats) {
        $pct = if ($null -ne $stats.ContextPercent) { "($([string]$stats.ContextPercent)%)" } else { '' }
        $line = 'ctx {0}/{1} {2} | in {3} [cached {4} | fresh {5}] | out {6}' -f `
            (Format-Compact $stats.ContextTokens), (Format-Compact $stats.ContextWindow), $pct, `
            (Format-Compact $stats.TotalInput), (Format-Compact $stats.TotalCachedInput), `
            (Format-Compact $stats.TotalNonCachedInput), (Format-Compact $stats.TotalOutput)
        Write-Host $line -ForegroundColor Cyan
    }
    Write-Host $body
    Write-Host ("next refresh in {0}s" -f $IntervalSeconds) -ForegroundColor DarkGray
    Start-Sleep -Seconds $IntervalSeconds
}