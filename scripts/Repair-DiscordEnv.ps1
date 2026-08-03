[CmdletBinding()]
param(
    [string]$EnvFile = (Join-Path (Split-Path $PSScriptRoot -Parent) ".env")
)

$ErrorActionPreference = "Stop"
$projectRoot = Split-Path $PSScriptRoot -Parent
$backupDirectory = Join-Path $projectRoot ".discord-state\backups"
$snowflakePattern = "^\d{17,20}$"
$tokenPattern = "^[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$"
$requiredKeys = @(
    "WORK_CHANNEL_ID",
    "CHAT_CHANNEL_ID",
    "APPROVER_USER_ID",
    "ORCH_BOT_TOKEN",
    "CLAUDE_BOT_TOKEN",
    "CODEX_BOT_TOKEN",
    "GEMINI_BOT_TOKEN"
)

if (-not (Test-Path -LiteralPath $EnvFile)) {
    throw ".env 파일을 찾을 수 없습니다: $EnvFile"
}

$values = @{}
foreach ($rawLine in Get-Content -LiteralPath $EnvFile -Encoding utf8) {
    $line = $rawLine.Trim()
    if (-not $line -or $line.StartsWith("#")) { continue }
    $separator = $line.IndexOf("=")
    if ($separator -lt 1) { continue }
    $key = $line.Substring(0, $separator).Trim()
    if ($key -notin $requiredKeys) { continue }
    $value = $line.Substring($separator + 1).Trim().Trim('"').Trim("'")
    $values[$key] = $value
}

$missing = @($requiredKeys | Where-Object { -not $values[$_] })
if ($missing.Count -gt 0) {
    throw "필수 Discord 설정이 비어 있습니다: $($missing -join ', ')"
}

foreach ($key in @("WORK_CHANNEL_ID", "CHAT_CHANNEL_ID", "APPROVER_USER_ID")) {
    if ($values[$key] -notmatch $snowflakePattern) {
        throw "$key 값이 17~20자리 Discord ID 형식이 아닙니다."
    }
}

foreach ($key in @("ORCH_BOT_TOKEN", "CLAUDE_BOT_TOKEN", "CODEX_BOT_TOKEN", "GEMINI_BOT_TOKEN")) {
    if ($values[$key] -notmatch $tokenPattern) {
        throw "$key 값이 Discord 봇 토큰 형식이 아닙니다."
    }
}

New-Item -ItemType Directory -Force -Path $backupDirectory | Out-Null
$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$backupFile = Join-Path $backupDirectory ".env.$timestamp.backup"
Copy-Item -LiteralPath $EnvFile -Destination $backupFile

$content = @(
    "# Discord Multi-Agent 실환경 설정"
    "# 보안: 이 파일은 Git에 포함하지 않으며 토큰을 채팅이나 문서에 붙여 넣지 않는다."
    ""
    "# Discord 채널 및 승인자 ID"
    "WORK_CHANNEL_ID=$($values.WORK_CHANNEL_ID)"
    "CHAT_CHANNEL_ID=$($values.CHAT_CHANNEL_ID)"
    "APPROVER_USER_ID=$($values.APPROVER_USER_ID)"
    ""
    "# Discord 봇 토큰"
    "ORCH_BOT_TOKEN=$($values.ORCH_BOT_TOKEN)"
    "CLAUDE_BOT_TOKEN=$($values.CLAUDE_BOT_TOKEN)"
    "CODEX_BOT_TOKEN=$($values.CODEX_BOT_TOKEN)"
    "GEMINI_BOT_TOKEN=$($values.GEMINI_BOT_TOKEN)"
)

$utf8WithoutBom = [System.Text.UTF8Encoding]::new($false)
[System.IO.File]::WriteAllText(
    (Resolve-Path -LiteralPath $EnvFile).Path,
    (($content -join "`n") + "`n"),
    $utf8WithoutBom
)

Write-Output "[OK] .env 정규화 완료"
Write-Output "[OK] UTF-8 BOM 없음"
Write-Output "[OK] Discord ID 3개 검증 완료"
Write-Output "[OK] 봇 토큰 4개 형식 검증 완료"
Write-Output "[OK] 백업 생성: $backupFile"
