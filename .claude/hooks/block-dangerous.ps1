# PreToolUse hook: blocks a short list of dangerous actions before they run.
#   - recursive force deletes (rm -rf, Remove-Item -Recurse -Force, rd /s)
#   - force pushes (git push --force, --force-with-lease, -f, +refspec)
#   - piping a download into a shell (curl | sh, iwr | iex, bash <(curl ...))
#   - reading .env files (.env.example, .sample, .template and .dist are allowed)
# Exit code 2 blocks the call and sends the message on stderr back to the agent.
# This mirrors permissions.deny in .claude/settings.json. The hook is the stronger check: it also
# sees compound commands, flag order and PowerShell syntax that deny patterns can miss.
$ErrorActionPreference = 'Stop'

function Block([string]$reason) {
    [Console]::Error.WriteLine("BLOCKED by .claude/hooks/block-dangerous.ps1: $reason. Leave it for a person to do.")
    exit 2
}

try {
    $hook = [Console]::In.ReadToEnd() | ConvertFrom-Json
} catch {
    Block 'could not read the hook input, so the call was not checked'
}

$tool = [string]$hook.tool_name
$in = $hook.tool_input

# A .env file name, as its own path segment or argument. Template copies are fine.
$envFile = '(?i)(^|[\\/\s"''=:])\.env(\.[\w.-]+)?(?=$|[\s"'';|&)*?])'
function IsEnvFile([string]$text) {
    foreach ($m in [regex]::Matches($text, $envFile)) {
        if ($m.Value -notmatch '(?i)\.env\.(example|sample|template|dist)$') { return $true }
    }
    return $false
}

if ($tool -in @('Read', 'Grep', 'Glob')) {
    $targets = @($in.file_path, $in.path, $in.glob)
    if ($tool -eq 'Glob') { $targets += $in.pattern }
    foreach ($t in $targets) {
        if ($t -and (IsEnvFile ([string]$t))) { Block "touching a .env file ($t)" }
    }
    exit 0
}

if ($tool -notin @('Bash', 'PowerShell')) { exit 0 }

$cmd = [string]$in.command
if (-not $cmd.Trim()) { exit 0 }

# Each statement on its own, so flags are only matched against the command they belong to.
$segments = [regex]::Split($cmd, '(?:&&|\|\||[;|&\r\n])') | ForEach-Object { $_.Trim() } | Where-Object { $_ }

foreach ($seg in $segments) {
    # rm -rf, rm -fr, rm -r -f, rm --recursive --force
    if ($seg -match '(?i)(^|[\s(])rm\s(.*)$') {
        $rest = $Matches[2]
        $rec = $rest -match '(?i)(^|\s)-[a-z]*r[a-z]*(\s|$)|--recursive'
        $frc = $rest -match '(?i)(^|\s)-[a-z]*f[a-z]*(\s|$)|--force'
        if ($rec -and $frc) { Block 'recursive force delete (rm -rf)' }
    }
    # Remove-Item / ri / del / erase with -Recurse and -Force
    if ($seg -match '(?i)(^|[\s(])(remove-item|ri|del|erase|rd|rmdir)\s(.*)$') {
        $rest = $Matches[3]
        if ($rest -match '(?i)-r(ecurse)?(\s|$)' -and $rest -match '(?i)-fo(rce)?(\s|$)') { Block 'recursive force delete (Remove-Item -Recurse -Force)' }
        if ($rest -match '(?i)(^|\s)/s(\s|$)') { Block 'recursive delete (rd /s, del /s)' }
    }
    # git push --force, --force-with-lease, -f, -fu, +main
    if ($seg -match '(?i)(^|[\s(])git(\s+-[-\w]+(\s+\S+)?)*\s+push\s(.*)$') {
        $rest = $Matches[4]
        if ($rest -match '(?i)--force|(^|\s)-[a-z]*f[a-z]*(\s|$)|(^|\s)\+\S') { Block 'force push (git push --force)' }
    }
}

# Download piped into a shell or interpreter.
$dl = '(curl|wget|iwr|irm|invoke-webrequest|invoke-restmethod)'
$sh = '(sudo\s+)?(sh|bash|zsh|dash|ksh|iex|invoke-expression|pwsh|powershell)'
if ($cmd -match "(?is)\b$dl\b[^`r`n]*\|\s*$sh\b") { Block 'piping a download into a shell (curl | sh)' }
if ($cmd -match "(?is)\b(iex|invoke-expression)\b[^`r`n]*\b($dl|downloadstring)\b") { Block 'executing a download (iex + iwr)' }
if ($cmd -match "(?is)\b(sh|bash|zsh|dash|ksh)\b[^`r`n]*(<\(|\`$\()\s*$dl\b") { Block 'running a download through a shell (bash <(curl ...))' }

# Reading .env files from the shell.
if (IsEnvFile $cmd) { Block 'a command that mentions a .env file' }

exit 0
