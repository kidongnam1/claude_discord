# setup-discord.ps1 — Discord Multi-Agent 설정 마법사
#
# 사용법: .\scripts\setup-discord.ps1
#
# - 7개 설정 값을 순서대로 물어보고 .env 파일을 자동 생성한다
# - 기존 .env가 있으면 현재 값을 기본값으로 보여주고 Enter만 누르면 유지
# - 채널 ID/승인자 ID는 CLAUDE.md에 이미 적힌 값을 기본값으로 미리 채운다
# - 봇 토큰 4개는 사용자가 직접 입력 (보안: 입력값을 화면에 다시 출력하지 않음)
# - 완료 후 DRY_RUN 테스트를 자동 실행한다

[CmdletBinding()]
param(
    [string]$EnvFile = ""
)

$ErrorActionPreference = "Stop"

$ProjectRoot = Split-Path -Parent $PSScriptRoot
if (-not $EnvFile) { $EnvFile = Join-Path $ProjectRoot ".env" }

# CLAUDE.md / log.md에서 알려진 기본값
$Defaults = @{
    WORK_CHANNEL_ID  = "1531495731167494194"
    CHAT_CHANNEL_ID  = "1531495800662921236"
    APPROVER_USER_ID = "1232185610282991698"
}

# 기존 .env 읽기 (있으면)
$Existing = @{}
if (Test-Path -LiteralPath $EnvFile) {
    foreach ($rawLine in Get-Content -LiteralPath $EnvFile -Encoding utf8) {
        $line = $rawLine.Trim()
        if (-not $line -or $line.StartsWith("#")) { continue }
        $sep = $line.IndexOf("=")
        if ($sep -lt 1) { continue }
        $key = $line.Substring(0, $sep).Trim()
        $val = $line.Substring($sep + 1).Trim().Trim('"').Trim("'")
        $Existing[$key] = $val
    }
    Write-Host "[INFO] 기존 .env 발견 — 현재 값을 기본값으로 사용합니다" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Discord Multi-Agent 설정 마법사" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  각 항목에 값을 입력하고 Enter를 누르세요." -ForegroundColor White
Write-Host "  괄호 안의 값은 기본값입니다 — 그대로 Enter를 누르면 유지됩니다." -ForegroundColor White
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# 7개 값 수집
$Config = @{}

# 1-3: 채널 ID + 승인자 ID (기본값 있음)
$keysWithDefaults = @(
    @{ Key = "WORK_CHANNEL_ID";  Desc = "작업 채널 ID (#작업)" }
    @{ Key = "CHAT_CHANNEL_ID";  Desc = "수다 채널 ID (#수다)" }
    @{ Key = "APPROVER_USER_ID"; Desc = "승인자 Discord 사용자 ID" }
)

foreach ($item in $keysWithDefaults) {
    $defaultVal = if ($Existing[$item.Key]) { $Existing[$item.Key] } else { $Defaults[$item.Key] }
    $input = Read-Host "$($item.Desc) [기본: $defaultVal]"
    $Config[$item.Key] = if ($input) { $input } else { $defaultVal }
}

# 4-7: 봇 토큰 (기본값 없음, 사용자 직접 입력)
$tokenKeys = @(
    @{ Key = "ORCH_BOT_TOKEN";   Desc = "오케스트레이터 봇 토큰 (선택, 비우면 Claude 봇 사용)" }
    @{ Key = "CLAUDE_BOT_TOKEN"; Desc = "Claude 워커 봇 토큰 (필수)" }
    @{ Key = "CODEX_BOT_TOKEN";  Desc = "Codex 워커 봇 토큰 (필수)" }
    @{ Key = "GEMINI_BOT_TOKEN"; Desc = "Gemini 워커 봇 토큰 (필수)" }
)

foreach ($item in $tokenKeys) {
    $defaultVal = if ($Existing[$item.Key]) { "****(기존값 유지하려면 Enter)" } else { "" }
    $input = Read-Host "$($item.Desc) $defaultVal"
    if ($Existing[$item.Key] -and -not $input) {
        $Config[$item.Key] = $Existing[$item.Key]
    } else {
        $Config[$item.Key] = $input
    }
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  입력값 확인 (토큰은 길이만 표시)" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

$displayKeys = @("WORK_CHANNEL_ID","CHAT_CHANNEL_ID","APPROVER_USER_ID","ORCH_BOT_TOKEN","CLAUDE_BOT_TOKEN","CODEX_BOT_TOKEN","GEMINI_BOT_TOKEN")
foreach ($key in $displayKeys) {
    $val = $Config[$key]
    if ($key -like "*TOKEN*") {
        $display = if ($val) { "SET (len=$($val.Length))" } else { "EMPTY" }
    } else {
        $display = if ($val) { $val } else { "EMPTY" }
    }
    Write-Host "  ${key}: $display"
}

Write-Host ""
$confirm = Read-Host "이 값으로 .env를 생성할까요? (Y/n)"
if ($confirm -and $confirm -notmatch "^[Yy]") {
    Write-Host "[취소] 설정을 저장하지 않았습니다." -ForegroundColor Yellow
    exit 0
}

# .env 파일 생성
$lines = @(
    "# Discord Multi-Agent 환경변수",
    "# 이 파일은 setup-discord.ps1에 의해 자동 생성되었습니다.",
    "# 생성 시간: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')",
    ""
)

foreach ($key in $displayKeys) {
    $lines += "$key=$($Config[$key])"
}

$lines += ""

# BOM 없는 UTF-8로 저장
$utf8NoBom = New-Object System.Text.UTF8Encoding $false
[System.IO.File]::WriteAllLines($EnvFile, ($lines -join "`n"), $utf8NoBom)

Write-Host ""
Write-Host "[OK] .env 생성 완료: $EnvFile" -ForegroundColor Green
Write-Host ""

# DRY_RUN 테스트
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  DRY_RUN 테스트 (실제 전송 없음)" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

$ScriptDir = $PSScriptRoot

# bash 기반 DRY_RUN (Git Bash 필요)
$bashPath = Get-Command bash -ErrorAction SilentlyContinue
if ($bashPath) {
    Write-Host "[1] new-thread.sh DRY_RUN:" -ForegroundColor White
    $result = & bash -c "cd '$ProjectRoot' && DRY_RUN=1 ./scripts/new-thread.sh '설정 테스트' 2>&1"
    Write-Host $result
    Write-Host ""

    Write-Host "[2] post-as.sh DRY_RUN:" -ForegroundColor White
    $result = & bash -c "cd '$ProjectRoot' && DRY_RUN=1 ./scripts/post-as.sh claude `"$($Config['WORK_CHANNEL_ID'])`" '설정 테스트 메시지' 2>&1"
    Write-Host $result
    Write-Host ""
} else {
    Write-Host "[SKIP] bash가 없어 DRY_RUN을 건너뜁니다" -ForegroundColor Yellow
}

Write-Host "========================================" -ForegroundColor Green
Write-Host "  설정 완료!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host ""
Write-Host "다음 단계:"
Write-Host "  1) 연결 검사: .\scripts\Test-DiscordConnection.ps1"
Write-Host "  2) 실전송 검사: .\scripts\Test-DiscordConnection.ps1 -SendLiveTest"
Write-Host "  3) 자동시작 등록: .\scripts\install-autostart.ps1"
Write-Host "  4) 오케스트레이터 실행: .\scripts\Start-DiscordOrchestratorVisible.ps1"
Write-Host ""
