<#
.SYNOPSIS
    Installs the "Codex counter" status line + token stats tool for Codex CLI.

.DESCRIPTION
    1. Merges token items into the Codex TUI status line in config.toml
       ([tui] status_line). Existing items are kept.
    2. Installs the "codex-context-stats" skill (SKILL.md + scripts) into the
       Codex home skills folder so the agent can report cached/non-cached
       token totals on demand.

    A timestamped backup of config.toml is created before any change.

.PARAMETER CodexHome
    Codex home to install into (default: $env:CODEX_HOME or %USERPROFILE%\.codex).

.PARAMETER Items
    Status line items to ensure are present. Default:
    used-tokens, context-window-size, total-input-tokens,
    total-output-tokens.

.PARAMETER NoSkill
    Skip the skill installation (status line only).

.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1
#>
[CmdletBinding()]
param(
    [string]$CodexHome,
    [string[]]$Items = @('used-tokens', 'context-window-size', 'total-input-tokens', 'total-output-tokens'),
    [switch]$NoSkill
)

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path

# --- resolve codex home -------------------------------------------------
function Get-HomePath {
    if ($CodexHome) {
        if (-not (Test-Path $CodexHome)) { throw "Codex home not found: $CodexHome" }
        return (Resolve-Path $CodexHome).Path
    }
    if ($env:CODEX_HOME) { return $env:CODEX_HOME }
    $up = $env:USERPROFILE
    if (-not $up) { $up = [Environment]::GetFolderPath('UserProfile') }
    return Join-Path $up '.codex'
}

$codexHomePath = Get-HomePath
Write-Output "Codex home: $codexHomePath"

# --- update config.toml --------------------------------------------------
$configPath = Join-Path $codexHomePath 'config.toml'
if (-not (Test-Path $configPath)) {
    New-Item -ItemType File -Path $configPath | Out-Null
    Write-Output "Created missing config: $configPath"
}
$backupPath = "$configPath.bak-" + (Get-Date).ToString('yyyyMMdd-HHmmss')
Copy-Item -LiteralPath $configPath -Destination $backupPath
Write-Output "Backup: $backupPath"

$content = Get-Content -LiteralPath $configPath -Raw
$lines = $content -split "`r?`n"

# collect existing status_line items (if any)
$existing = @()
$existingLineIndex = -1
for ($i = 0; $i -lt $lines.Count; $i++) {
    if ($lines[$i] -match '^\s*status_line\s*=\s*\[([^\]]*)\]') {
        $existingLineIndex = $i
        $existing = @([regex]::Matches($Matches[1], '"([^"]*)"') | ForEach-Object { $_.Groups[1].Value })
        break
    }
}

# merged list: existing order first, then new items not already present
$merged = New-Object System.Collections.Generic.List[string]
foreach ($item in $existing) { $merged.Add($item) }
foreach ($item in $Items) { if (-not $merged.Contains($item)) { $merged.Add($item) } }

$newLine = 'status_line = [' + (($merged | ForEach-Object { '"' + $_ + '"' }) -join ', ') + ']'
Write-Output ("Status line items: {0}" -f ($merged -join ', '))

if ($existingLineIndex -ge 0) {
    $lines[$existingLineIndex] = $newLine
}
else {
    $tuiIndex = -1
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '^\s*\[tui\]\s*$') { $tuiIndex = $i; break }
    }
    if ($tuiIndex -ge 0) {
        $lines = @($lines[0..$tuiIndex] + @($newLine) + $lines[($tuiIndex + 1)..($lines.Count - 1)])
    }
    else {
        $lines = @($lines + @('', '[tui]', $newLine))
    }
}

Set-Content -LiteralPath $configPath -Value (($lines -join "`r`n")) -Encoding UTF8
Write-Output "Updated: $configPath"

# --- install skill ---------------------------------------------------------
if (-not $NoSkill) {
    $skillName = 'codex-context-stats'
    $skillDest = Join-Path $codexHomePath (Join-Path 'skills' $skillName)
    $scriptsDest = Join-Path $skillDest 'scripts'
    New-Item -ItemType Directory -Force -Path $scriptsDest | Out-Null

    $skillSrc = Join-Path $repoRoot 'skill'
    Copy-Item -LiteralPath (Join-Path $skillSrc 'SKILL.md') -Destination (Join-Path $skillDest 'SKILL.md') -Force
    Copy-Item -LiteralPath (Join-Path (Join-Path $repoRoot 'src') 'codex-context-stats.ps1') -Destination (Join-Path $scriptsDest 'codex-context-stats.ps1') -Force
    Copy-Item -LiteralPath (Join-Path (Join-Path $repoRoot 'src') 'codex-context-watch.ps1') -Destination (Join-Path $scriptsDest 'codex-context-watch.ps1') -Force
    Write-Output "Skill installed: $skillDest"
}

Write-Output ''
Write-Output 'Done. Restart Codex (or start a new session) to see the status line items.'
Write-Output 'Try the cached/non-cached breakdown any time by asking Codex for "token usage",'
Write-Output 'or run:  powershell -NoProfile -ExecutionPolicy Bypass -File <repo>\src\codex-context-stats.ps1 -Format table'




