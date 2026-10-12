<#
.SYNOPSIS
    Removes the "Codex counter" installation: strips the token items it added
    from [tui] status_line and deletes the codex-context-stats skill.

.PARAMETER CodexHome
    Codex home to uninstall from (default: $env:CODEX_HOME or %USERPROFILE%\.codex).

.PARAMETER Items
    Items to remove from status_line (default: the ones install.ps1 adds).

.PARAMETER RemoveAllStatusLine
    Remove the whole status_line setting instead of just the added items.
#>
[CmdletBinding()]
param(
    [string]$CodexHome,
    [string[]]$Items = @('used-tokens', 'context-window-size', 'total-input-tokens', 'total-output-tokens'),
    [switch]$RemoveAllStatusLine
)

$ErrorActionPreference = 'Stop'

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

# --- config.toml ----------------------------------------------------------
$configPath = Join-Path $codexHomePath 'config.toml'
if (Test-Path $configPath) {
    $backupPath = "$configPath.bak-" + (Get-Date).ToString('yyyyMMdd-HHmmss')
    Copy-Item -LiteralPath $configPath -Destination $backupPath
    Write-Output "Backup: $backupPath"

    $lines = Get-Content -LiteralPath $configPath
    $kept = New-Object System.Collections.Generic.List[string]
    $removedLine = $false
    foreach ($line in $lines) {
        if ($line -match '^\s*status_line\s*=\s*\[([^\]]*)\]') {
            $removedLine = $true
            if ($RemoveAllStatusLine) { continue }
            $parsedItems = @([regex]::Matches($Matches[1], '"([^"]*)"') | ForEach-Object { $_.Groups[1].Value })
            $remaining = @($parsedItems | Where-Object { $Items -notcontains $_ })
            if ($remaining.Count -gt 0) {
                $kept.Add('status_line = [' + (($remaining | ForEach-Object { '"' + $_ + '"' }) -join ', ') + ']')
            }
            continue
        }
        $kept.Add($line)
    }
    if ($removedLine) {
        Set-Content -LiteralPath $configPath -Value ($kept -join "`r`n") -Encoding UTF8
        Write-Output "status_line updated in: $configPath"
    }
    else {
        Write-Output "No status_line setting found in config.toml; nothing to change."
    }
}
else {
    Write-Output "No config.toml found; nothing to change."
}

# --- skill ------------------------------------------------------------------
$skillDest = Join-Path $codexHomePath (Join-Path 'skills' 'codex-context-stats')
if (Test-Path $skillDest) {
    Remove-Item -LiteralPath $skillDest -Recurse -Force
    Write-Output "Removed skill: $skillDest"
}
else {
    Write-Output "Skill not present; nothing to remove."
}

Write-Output ''
Write-Output 'Uninstall complete. Restart Codex to apply.'


