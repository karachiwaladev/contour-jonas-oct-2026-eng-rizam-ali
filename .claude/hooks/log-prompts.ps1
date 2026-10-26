# Stop hook: append the user prompts added to the transcript since the last stop
# to .claude/prompts.jsonl, one JSON object per line.
$ErrorActionPreference = 'Stop'

$hook = [Console]::In.ReadToEnd() | ConvertFrom-Json
$transcript = $hook.transcript_path
if (-not $transcript -or -not (Test-Path -LiteralPath $transcript)) { exit 0 }

$root = if ($env:CLAUDE_PROJECT_DIR) { $env:CLAUDE_PROJECT_DIR } else { $hook.cwd }
$logFile = Join-Path $root '.claude\prompts.jsonl'
$stateDir = Join-Path $root '.claude\hooks\state'
$stateFile = Join-Path $stateDir "$($hook.session_id).offset"
New-Item -ItemType Directory -Force -Path $stateDir | Out-Null

# Number of transcript lines already processed for this session.
$offset = 0
if (Test-Path -LiteralPath $stateFile) { $offset = [int](Get-Content -LiteralPath $stateFile -Raw) }

$lines = [IO.File]::ReadAllLines($transcript, [Text.Encoding]::UTF8)
if ($lines.Count -le $offset) { exit 0 }

$out = New-Object System.Text.StringBuilder
for ($i = $offset; $i -lt $lines.Count; $i++) {
    if (-not $lines[$i].Trim()) { continue }
    try { $entry = $lines[$i] | ConvertFrom-Json } catch { continue }

    # Typed prompts only: skip tool results, and isMeta entries (skill bodies, scheduled fires).
    if ($entry.type -ne 'user' -or $entry.isMeta) { continue }
    $content = $entry.message.content
    if ($content -is [string]) {
        $text = $content
    } else {
        $parts = @($content | Where-Object { $_.type -eq 'text' -and $_.text -notmatch '^\s*<(system-reminder|ide_)' } | ForEach-Object { $_.text })
        $text = $parts -join "`n"
    }
    if (-not $text.Trim()) { continue }

    $record = [ordered]@{
        timestamp  = $entry.timestamp
        session_id = $hook.session_id
        uuid       = $entry.uuid
        prompt     = $text
    }
    [void]$out.AppendLine(($record | ConvertTo-Json -Compress))
}

$utf8 = New-Object System.Text.UTF8Encoding($false)
if ($out.Length -gt 0) { [IO.File]::AppendAllText($logFile, $out.ToString(), $utf8) }
[IO.File]::WriteAllText($stateFile, [string]$lines.Count, $utf8)
