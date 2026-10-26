# Commits and pushes local changes to GitHub main through the API (git is not installed here).
# Runs as a Stop hook, and the factory-loop skill calls it directly before answering a ticket.
#
# Safety rules (the factory must never do anything destructive):
#   - only adds or updates files; a file deleted locally is NEVER deleted on GitHub
#   - never force-pushes: the branch only moves forward
#   - a file that changed on GitHub since the last sync is skipped, not overwritten
#   - private or secret-looking files are never uploaded
#
# Usage: sync-to-github.ps1 [-Message "text"] [-DryRun]
param(
    [string]$Message,
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
$Repo = 'karachiwaladev/contour-jonas-oct-2026-eng-rizam-ali'
$Branch = 'main'
$MaxBytes = 1MB

# Never uploaded: local-only logs/state, and anything that commonly holds secrets.
$ExcludeDirs = @('.git', 'node_modules', '.claude/hooks/state')
$ExcludeFiles = @('.claude/prompts.jsonl', '.claude/scheduled_tasks.lock', '.claude/settings.local.json')
$SecretNames = '(^|/)(\.env(\..*)?|.*\.(key|pem|pfx|p12)|id_rsa.*|credentials.*)$'
$SecretText = '(gh[opsu]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|sk-[A-Za-z0-9_-]{20,}|AKIA[0-9A-Z]{16}|-----BEGIN [A-Z ]*PRIVATE KEY-----)'

function Say($text) { [Console]::Error.WriteLine("[sync] $text") }

# Only one sync at a time (the loop and the Stop hook can overlap).
$mutex = New-Object System.Threading.Mutex($false, 'Global\factory-sync-to-github')
if (-not $mutex.WaitOne(0)) { Say 'another sync is running, skipping'; exit 0 }

try {
    if (-not (Get-Command gh -ErrorAction SilentlyContinue)) { Say 'gh CLI not found, nothing synced'; exit 0 }

    $root = if ($env:CLAUDE_PROJECT_DIR) { $env:CLAUDE_PROJECT_DIR } else { (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path }
    $root = $root.TrimEnd('\')
    $stateDir = Join-Path $root '.claude\hooks\state'
    $stateFile = Join-Path $stateDir 'synced.json'
    $tmp = Join-Path $env:TEMP ("factory-sync-" + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Force -Path $stateDir, $tmp | Out-Null
    $utf8 = New-Object System.Text.UTF8Encoding($false)

    function Invoke-Api([string]$Method, [string]$Path, $Body) {
        if ($null -ne $Body) {
            $f = Join-Path $tmp ([guid]::NewGuid().ToString('N') + '.json')
            [IO.File]::WriteAllText($f, ($Body | ConvertTo-Json -Depth 6), $utf8)
            $out = gh api -X $Method $Path --input $f
        } else {
            $out = gh api -X $Method $Path
        }
        if ($LASTEXITCODE -ne 0) { throw "gh api $Method $Path failed" }
        return ($out | ConvertFrom-Json)
    }

    function Get-BlobSha([byte[]]$bytes) {
        $header = [Text.Encoding]::ASCII.GetBytes("blob $($bytes.Length)`0")
        $sha1 = [Security.Cryptography.SHA1]::Create()
        $all = New-Object byte[] ($header.Length + $bytes.Length)
        [Array]::Copy($header, 0, $all, 0, $header.Length)
        [Array]::Copy($bytes, 0, $all, $header.Length, $bytes.Length)
        return (($sha1.ComputeHash($all) | ForEach-Object { $_.ToString('x2') }) -join '')
    }

    # Remote state
    $ref = Invoke-Api GET "repos/$Repo/git/ref/heads/$Branch" $null
    $headSha = $ref.object.sha
    $headCommit = Invoke-Api GET "repos/$Repo/git/commits/$headSha" $null
    $remoteTree = Invoke-Api GET "repos/$Repo/git/trees/$($headCommit.tree.sha)?recursive=1" $null
    $remote = @{}
    foreach ($e in $remoteTree.tree) { if ($e.type -eq 'blob') { $remote[$e.path] = $e.sha } }

    # Last-synced SHAs. First run: trust what is on GitHub right now.
    $state = @{}
    if (Test-Path -LiteralPath $stateFile) {
        (Get-Content -LiteralPath $stateFile -Raw | ConvertFrom-Json).PSObject.Properties | ForEach-Object { $state[$_.Name] = $_.Value }
    } else {
        foreach ($k in $remote.Keys) { $state[$k] = $remote[$k] }
    }

    # Decide what to push
    $toPush = @(); $conflicts = @(); $skipped = @()
    $files = Get-ChildItem -LiteralPath $root -Recurse -File -Force -ErrorAction SilentlyContinue
    foreach ($file in $files) {
        $rel = $file.FullName.Substring($root.Length + 1) -replace '\\', '/'
        if ($ExcludeFiles -contains $rel) { continue }
        if ($ExcludeDirs | Where-Object { $rel -eq $_ -or $rel.StartsWith("$_/") }) { continue }
        if ($rel -match $SecretNames) { $skipped += "$rel (looks like a secrets file)"; continue }
        if ($file.Length -gt $MaxBytes) { $skipped += "$rel (over 1 MB)"; continue }

        $bytes = [IO.File]::ReadAllBytes($file.FullName)
        $local = Get-BlobSha $bytes
        $r = $remote[$rel]; $s = $state[$rel]

        if ($local -eq $r) { $state[$rel] = $r; continue }                       # already identical
        $text = [Text.Encoding]::UTF8.GetString($bytes)
        if ($text -match $SecretText) { $skipped += "$rel (contains something that looks like a token)"; continue }

        if (-not $r -and -not $s) { $toPush += @{ path = $rel; bytes = $bytes; sha = $local; kind = 'add' }; continue }
        if ($r -and $r -eq $s)     { $toPush += @{ path = $rel; bytes = $bytes; sha = $local; kind = 'update' }; continue }
        $conflicts += $rel                                                       # GitHub changed (or was deleted) since last sync
    }

    foreach ($c in $conflicts) { Say "SKIPPED $c : it changed on GitHub since the last sync, not overwriting" }
    foreach ($k in $skipped) { Say "SKIPPED $k" }

    if ($toPush.Count -eq 0) {
        if (-not $DryRun) { [IO.File]::WriteAllText($stateFile, ($state | ConvertTo-Json), $utf8) }
        Say 'nothing to push'
        if ($conflicts.Count -gt 0) { Write-Output (@{ systemMessage = "Sync skipped $($conflicts.Count) file(s) changed on GitHub: $($conflicts -join ', ')" } | ConvertTo-Json -Compress) }
        exit 0
    }

    if ($DryRun) {
        foreach ($p in $toPush) { Say "would push ($($p.kind)): $($p.path)" }
        exit 0
    }

    $entries = @()
    foreach ($p in $toPush) {
        $blob = Invoke-Api POST "repos/$Repo/git/blobs" @{ content = [Convert]::ToBase64String($p.bytes); encoding = 'base64' }
        $entries += @{ path = $p.path; mode = '100644'; type = 'blob'; sha = $blob.sha }
    }
    $tree = Invoke-Api POST "repos/$Repo/git/trees" @{ base_tree = $headCommit.tree.sha; tree = $entries }

    if (-not $Message) {
        $names = ($toPush | ForEach-Object { $_.path }) -join ', '
        if ($names.Length -gt 120) { $names = $names.Substring(0, 117) + '...' }
        $Message = "Auto-sync on stop: $($toPush.Count) file(s): $names"
    }
    $commit = Invoke-Api POST "repos/$Repo/git/commits" @{ message = $Message; tree = $tree.sha; parents = @($headSha) }

    # force=false: if main moved in the meantime this fails instead of overwriting anything.
    Invoke-Api PATCH "repos/$Repo/git/refs/heads/$Branch" @{ sha = $commit.sha; force = $false } | Out-Null

    foreach ($p in $toPush) { $state[$p.path] = $p.sha }
    [IO.File]::WriteAllText($stateFile, ($state | ConvertTo-Json), $utf8)

    $short = $commit.sha.Substring(0, 7)
    Say "pushed $($toPush.Count) file(s) as $short"
    Write-Output (@{ systemMessage = "Pushed $($toPush.Count) file(s) to $Repo main ($short)" } | ConvertTo-Json -Compress)
}
catch {
    Say "FAILED: $($_.Exception.Message) (nothing was force-pushed or deleted)"
    exit 0
}
finally {
    if ($tmp -and (Test-Path -LiteralPath $tmp)) { Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue }
    $mutex.ReleaseMutex()
}
