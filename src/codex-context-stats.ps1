<#
.SYNOPSIS
    Reports token usage for a Codex CLI session: tokens currently in context,
    the model context window size, and conversation totals split into cached
    vs non-cached input tokens.

.DESCRIPTION
    Reads the session rollout JSONL stored in the Codex home (default: %USERPROFILE%\.codex,
    or $env:CODEX_HOME when set) and reports the data from the latest
    "token_count" event:

      - Context tokens      : input size of the most recent API request (current context)
      - Context window      : model context window size
      - Conversation input  : total input tokens sent over the whole conversation
      - Cached input        : input tokens served from the provider prompt cache
      - Non-cached input    : input tokens that were NOT cached (input - cached - cache-write)
      - Conversation output : total output tokens (including reasoning tokens)

    Works with Windows PowerShell 5.1 and PowerShell 7.

.PARAMETER SessionId
    Session/thread id to report (the id embedded in the rollout file name).
    Default: the most recently modified rollout in the Codex home.

.PARAMETER Format
    Output format:
      line  - one compact line, e.g. "ctx 34.7k/124.5k (27.9%) | in 374.9k [cached 356.7k | fresh 18.2k] | out 13.4k"
      table - human readable multi-line report
      json  - machine readable JSON object
    Default: line.

.PARAMETER CodexHome
    Override the Codex home directory (default: $env:CODEX_HOME or %USERPROFILE%\.codex).

.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File .\codex-context-stats.ps1

.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File .\codex-context-stats.ps1 -Format table

.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File .\codex-context-stats.ps1 -SessionId 01a12ef0-999f-71e3-839d-572f5d68ce32 -Format json
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string]$SessionId,

    [ValidateSet('line', 'table', 'json')]
    [string]$Format = 'line',

    [string]$CodexHome
)

$ErrorActionPreference = 'Stop'

function Get-CodexHomePath {
    param([string]$Override)
    if ($Override) {
        if (-not (Test-Path $Override)) { throw "Codex home not found: $Override" }
        return (Resolve-Path $Override).Path
    }
    if ($env:CODEX_HOME) { return $env:CODEX_HOME }
    $userProfile = $env:USERPROFILE
    if (-not $userProfile) { $userProfile = [Environment]::GetFolderPath('UserProfile') }
    return Join-Path $userProfile '.codex'
}

function Format-Compact {
    param([long]$Value)
    if ($null -eq $Value) { return '?' }
    $abs = [Math]::Abs([long]$Value)
    if ($abs -ge 1000000) { return ('{0:N1}M' -f ($Value / 1000000)) }
    if ($abs -ge 1000)    { return ('{0:N1}k' -f ($Value / 1000)) }
    return [string]$Value
}


function Open-SessionRollout {
    param([string]$Path)
    try {
        $fs = [System.IO.File]::Open($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
        return [System.IO.StreamReader]::new($fs)
    }
    catch {
        $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("codex-rollout-" + [guid]::NewGuid().ToString('N') + '.jsonl')
        try {
            Copy-Item -LiteralPath $Path -Destination $tmp -ErrorAction Stop
            return [System.IO.File]::OpenText($tmp)
        }
        catch {
            throw "Cannot read rollout file (locked by Codex and not copyable): $Path"
        }
    }
}
function Get-CodexContextStats {
    param([string]$CodexHomePath, [string]$Sid)

    $sessionsDir = Join-Path $CodexHomePath 'sessions'
    if (-not (Test-Path $sessionsDir)) { throw "Codex sessions directory not found: $sessionsDir" }

    if ($Sid) {
        $file = Get-ChildItem -Path $sessionsDir -Recurse -Filter ("*" + $Sid + "*.jsonl") -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if (-not $file) { throw "No rollout found for session id '$Sid' under $sessionsDir" }
    }
    else {
        $file = Get-ChildItem -Path $sessionsDir -Recurse -Filter 'rollout-*.jsonl' -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if (-not $file) { throw "No rollout files found under $sessionsDir" }
    }

    $metaSessionId = $null; $metaCwd = $null; $metaProvider = $null; $metaVersion = $null
    $contextWindow = $null
    $lastTokenInfo = $null
    $lastUsageRecord = $null
    $lastEventTime = $null

    $reader = Open-SessionRollout -Path $file.FullName
    try {
        while ($null -ne ($line = $reader.ReadLine())) {
            if ($line -notmatch '"type"') { continue }
            $obj = $null
            try { $obj = $line | ConvertFrom-Json } catch { continue }
            if (-not $obj) { continue }
            $payload = $obj.payload
            $subType = $null
            if ($payload -and $payload.PSObject.Properties['type']) { $subType = $payload.type }
            else { $subType = $obj.type }

            switch ($subType) {
                'session_meta' {
                    if ($payload) {
                        $metaSessionId = $payload.session_id
                        $metaCwd = $payload.cwd
                        $metaProvider = $payload.model_provider
                        $metaVersion = $payload.cli_version
                    }
                }
                'task_started' {
                    if ($payload -and $payload.PSObject.Properties['model_context_window']) {
                        $contextWindow = [long]$payload.model_context_window
                    }
                }
                'turn_context' {
                    if ($payload -and $payload.PSObject.Properties['model_context_window']) {
                        $contextWindow = [long]$payload.model_context_window
                    }
                }
                'token_count' {
                    if ($payload -and $payload.info) {
                        $lastTokenInfo = $payload.info
                        if ($obj.timestamp) { $lastEventTime = [DateTimeOffset]::Parse($obj.timestamp).LocalDateTime }
                    }
                }
                'token_usage_record' {
                    if ($payload) {
                        $lastUsageRecord = $payload
                        if ($obj.timestamp) { $lastEventTime = [DateTimeOffset]::Parse($obj.timestamp).LocalDateTime }
                    }
                }
            }
        }
    }
    finally { $reader.Dispose() }

    if (-not $lastTokenInfo -and -not $lastUsageRecord) {
        throw "No token usage recorded in $($file.Name) yet - send a message in that session first."
    }

    if ($lastTokenInfo) {
        $last  = $lastTokenInfo.last_token_usage
        $total = $lastTokenInfo.total_token_usage
        if (-not $contextWindow -and $lastTokenInfo.model_context_window) {
            $contextWindow = [long]$lastTokenInfo.model_context_window
        }
    }
    else {
        $last  = $lastUsageRecord.usage
        $total = $lastUsageRecord.thread_token_usage
    }

    $totalInput      = [long]$total.input_tokens
    $totalCached     = [long]$total.cached_input_tokens
    $totalCacheWrite = [long]$total.cache_write_input_tokens
    $totalNonCached  = $totalInput - $totalCached - $totalCacheWrite
    if ($totalNonCached -lt 0) { $totalNonCached = 0 }
    if ($contextWindow -and $contextWindow -gt 0) {
        $contextPercent = [Math]::Round(100.0 * [double]$last.input_tokens / [double]$contextWindow, 1)
    }
    else {
        $contextPercent = $null
    }
    $contextCachedPct = $null
    if ([long]$last.input_tokens -gt 0) {
        $contextCachedPct = [Math]::Round(100.0 * [double]$last.cached_input_tokens / [double]$last.input_tokens, 1)
    }
    $cacheRatio = $null
    if ($totalInput -gt 0) {
        $cacheRatio = [Math]::Round(100.0 * [double]$totalCached / [double]$totalInput, 1)
    }

    [pscustomobject]@{
        SourceFile             = $file.FullName
        SessionId              = if ($metaSessionId) { $metaSessionId } else { $file.BaseName }
        Cwd                    = $metaCwd
        ModelProvider          = $metaProvider
        CliVersion             = $metaVersion
        ContextWindow          = $contextWindow
        ContextTokens          = [long]$last.input_tokens
        ContextCached          = [long]$last.cached_input_tokens
        ContextPercent         = $contextPercent
        ContextCachedPercent   = $contextCachedPct
        TotalInput             = $totalInput
        TotalCachedInput       = $totalCached
        TotalCacheWriteInput   = $totalCacheWrite
        TotalNonCachedInput    = $totalNonCached
        CacheRatioPercent      = $cacheRatio
        TotalOutput            = [long]$total.output_tokens
        TotalReasoningOutput   = [long]$total.reasoning_output_tokens
        TotalAll               = [long]$total.total_tokens
        LastUpdated            = if ($lastEventTime) { $lastEventTime } else { $file.LastWriteTime }
        LastUpdatedUtc         = if ($lastEventTime) { $lastEventTime.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ') } else { $null }
    }
}

function Format-Line {
    param($s)
    $window = if ($s.ContextWindow) { Format-Compact $s.ContextWindow } else { '?' }
    $pct = if ($null -ne $s.ContextPercent) { "($([string]$s.ContextPercent)%)" } else { '' }
    $line = 'ctx {0}/{1} {2} | in {3} [cached {4} | fresh {5}] | out {6}' -f `
        (Format-Compact $s.ContextTokens), $window, $pct, `
        (Format-Compact $s.TotalInput), (Format-Compact $s.TotalCachedInput), `
        (Format-Compact $s.TotalNonCachedInput), (Format-Compact $s.TotalOutput)
    return $line
}

function Format-Table {
    param($s)
    $pct = if ($null -ne $s.ContextPercent) { [string]$s.ContextPercent } else { '?' }
    $cacheHit = if ($null -ne $s.ContextCachedPercent) { [string]$s.ContextCachedPercent } else { '?' }
    $ratio = if ($null -ne $s.CacheRatioPercent) { [string]$s.CacheRatioPercent } else { '?' }
    $out = @(
        ('Codex context stats')
        ('===================')
        ('  Session         : {0}' -f $s.SessionId)
        ('  Provider        : {0}' -f ($(if ($s.ModelProvider) { $s.ModelProvider } else { '?' })))
        ('  Codex version   : {0}' -f ($(if ($s.CliVersion) { $s.CliVersion } else { '?' })))
        ('  Working dir     : {0}' -f ($(if ($s.Cwd) { $s.Cwd } else { '?' })))
        ('')
        ('  Context now     : {0} tokens in a {1} window ({2}% full)' -f (Format-Compact $s.ContextTokens), ($(if ($s.ContextWindow) { Format-Compact $s.ContextWindow } else { '?' })), $pct)
        ('  Context cached  : {0} of {1} current context served from cache ({2}%)' -f (Format-Compact $s.ContextCached), (Format-Compact $s.ContextTokens), $cacheHit)
        ('')
        ('  Conversation totals (input = context sent to the model)')
        ('    input total   : {0}' -f (Format-Compact $s.TotalInput))
        ('    cached        : {0} ({1}% of input)' -f (Format-Compact $s.TotalCachedInput), $ratio)
        ('    non-cached    : {0} (prompt + first-time cache writes not served from cache)' -f (Format-Compact $s.TotalNonCachedInput))
        ('    cache writes  : {0}' -f (Format-Compact $s.TotalCacheWriteInput))
        ('    output        : {0} (reasoning: {1})' -f (Format-Compact $s.TotalOutput), (Format-Compact $s.TotalReasoningOutput))
        ('    all tokens    : {0}' -f (Format-Compact $s.TotalAll))
        ('')
        ('  Source          : {0}' -f $s.SourceFile)
        ('  Last updated    : {0}' -f $s.LastUpdated.ToString('yyyy-MM-dd HH:mm:ss'))
    )
    return ($out -join [Environment]::NewLine)
}

try {
    $codexHomePath = Get-CodexHomePath -Override $CodexHome
    $stats = Get-CodexContextStats -CodexHomePath $codexHomePath -Sid $SessionId
    switch ($Format) {
        'line'  { Format-Line $stats }
        'table' { Format-Table $stats }
        'json'  { $stats | ConvertTo-Json -Depth 4 }
    }
}
catch {
    Write-Error $_.Exception.Message
    exit 1
}


