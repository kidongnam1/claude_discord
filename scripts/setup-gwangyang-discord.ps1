# setup-gwangyang-discord.ps1 — 광양 PC에서 Discord 오케스트레이터 설정
#
# 사용법: 관리자 PowerShell에서 실행
#   Set-ExecutionPolicy Bypass -Scope Process
#   .\setup-gwangyang-discord.ps1
#
# 이 스크립트는 다음을 수행한다:
# 1. bun 설치 (npm install -g bun)
# 2. ~/.claude/channels/discord/.env 생성 (DISCORD_BOT_TOKEN)
# 3. ~/.claude/channels/discord/access.json 생성
# 4. .discord-state/Start-DiscordOrchestrator.ps1 생성
# 5. 자동시작 바로가기 등록

[CmdletBinding()]
param(
    [string]$ProjectRoot = "D:\program\claude_discord"
)

$ErrorActionPreference = "Stop"

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  광양 PC Discord 오케스트레이터 설정" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# 1. bun 설치 확인
Write-Host "[1/5] bun 설치 확인 중..." -ForegroundColor Yellow
$bunCmd = Get-Command bun -ErrorAction SilentlyContinue
if (-not $bunCmd) {
    Write-Host "  bun 미설치 — 설치 중..." -ForegroundColor Yellow
    npm install -g bun 2>&1 | Out-Null
    $bunCmd = Get-Command bun -ErrorAction SilentlyContinue
    if ($bunCmd) {
        Write-Host "  [OK] bun 설치 완료: $($bunCmd.Source)" -ForegroundColor Green
    } else {
        Write-Host "  [ERROR] bun 설치 실패 — npm install -g bun 수동 실행 필요" -ForegroundColor Red
        exit 1
    }
} else {
    Write-Host "  [OK] bun 이미 설치됨: $($bunCmd.Source)" -ForegroundColor Green
}

# 2. ~/.claude/channels/discord/.env 생성
Write-Host ""
Write-Host "[2/5] Discord 플러그인 .env 생성 중..." -ForegroundColor Yellow
$discordStateDir = Join-Path $env:USERPROFILE ".claude\channels\discord"
if (-not (Test-Path $discordStateDir)) {
    New-Item -ItemType Directory -Path $discordStateDir -Force | Out-Null
}

$discordEnvPath = Join-Path $discordStateDir ".env"
# 프로젝트 .env에서 CLAUDE_BOT_TOKEN 읽기
$projectEnv = Join-Path $ProjectRoot ".env"
if (Test-Path $projectEnv) {
    $claudeToken = ""
    foreach ($line in Get-Content $projectEnv -Encoding utf8) {
        if ($line -match "^CLAUDE_BOT_TOKEN=(.+)$") {
            $claudeToken = $matches[1].Trim()
            break
        }
    }
    if ($claudeToken) {
        "DISCORD_BOT_TOKEN=$claudeToken" | Out-File -FilePath $discordEnvPath -Encoding utf8 -NoNewline
        Write-Host "  [OK] $discordEnvPath 생성 완료 (CL-Worker 토큰)" -ForegroundColor Green
    } else {
        Write-Host "  [ERROR] CLAUDE_BOT_TOKEN을 .env에서 찾을 수 없습니다" -ForegroundColor Red
        exit 1
    }
} else {
    Write-Host "  [ERROR] 프로젝트 .env 파일이 없습니다: $projectEnv" -ForegroundColor Red
    Write-Host "  먼저 setup-discord.ps1을 실행하여 .env를 생성하세요" -ForegroundColor Yellow
    exit 1
}

# 3. access.json 생성
Write-Host ""
Write-Host "[3/5] access.json 생성 중..." -ForegroundColor Yellow
$accessPath = Join-Path $discordStateDir "access.json"
$accessTemplate = Join-Path $ProjectRoot "docs\local-setup-backup\access.json.example"
if (Test-Path $accessTemplate) {
    Copy-Item $accessTemplate $accessPath -Force
    Write-Host "  [OK] $accessPath 생성 완료 (템플릿에서 복사)" -ForegroundColor Green
} else {
    # 템플릿이 없으면 직접 생성
    $accessJson = @"
{
  "dmPolicy": "allowlist",
  "allowFrom": ["1232185610282991698"],
  "groups": {
    "1531495731167494194": {
      "allowFrom": ["1232185610282991698"],
      "requireMention": false
    },
    "1531495800662921236": {
      "allowFrom": ["1232185610282991698"],
      "requireMention": false
    }
  },
  "mentionPatterns": [],
  "pending": {}
}
"@
    $accessJson | Out-File -FilePath $accessPath -Encoding utf8 -NoNewline
    Write-Host "  [OK] $accessPath 생성 완료 (직접 생성)" -ForegroundColor Green
}

# 4. .discord-state/Start-DiscordOrchestrator.ps1 생성
Write-Host ""
Write-Host "[4/5] 오케스트레이터 런처 생성 중..." -ForegroundColor Yellow
$discordStateProject = Join-Path $ProjectRoot ".discord-state"
if (-not (Test-Path $discordStateProject)) {
    New-Item -ItemType Directory -Path $discordStateProject -Force | Out-Null
}
$launcherPath = Join-Path $discordStateProject "Start-DiscordOrchestrator.ps1"
$launcherTemplate = Join-Path $ProjectRoot "docs\local-setup-backup\Start-DiscordOrchestrator.ps1.example"
if (Test-Path $launcherTemplate) {
    Copy-Item $launcherTemplate $launcherPath -Force
    Write-Host "  [OK] $launcherPath 생성 완료 (템플릿에서 복사)" -ForegroundColor Green
} else {
    Write-Host "  [WARN] 템플릿 없음 — docs/local-setup-backup/에서 수동 복사 필요" -ForegroundColor Yellow
}

# 5. 자동시작 바로가기 등록
Write-Host ""
Write-Host "[5/5] 자동시작 등록 중..." -ForegroundColor Yellow
$installScript = Join-Path $ProjectRoot "scripts\install-autostart.ps1"
if (Test-Path $installScript) {
    & $installScript
} else {
    Write-Host "  [WARN] install-autostart.ps1 없음 — 수동 실행 필요" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host "  광양 PC 설정 완료!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host ""
Write-Host "다음 단계:"
Write-Host "  1) .env 파일에 봇 토큰 입력 (아직 안 한 경우)"
Write-Host "     powershell -ExecutionPolicy Bypass -File scripts\setup-discord.ps1"
Write-Host ""
Write-Host "  2) 오케스트레이터 실행:"
Write-Host "     powershell -ExecutionPolicy Bypass -File scripts\Start-DiscordOrchestratorVisible.ps1"
Write-Host ""
Write-Host "  3) 폰 디스코드 #작업 채널에서 테스트:"
Write-Host "     '안녕'이라고 적으면 오케스트레이터가 응답"
Write-Host ""
