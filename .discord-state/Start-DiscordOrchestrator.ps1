# Start-DiscordOrchestrator.ps1 — Windows용 Discord 오케스트레이터 런처
#
# Start-DiscordOrchestratorVisible.ps1이 Windows Terminal을 띄운 뒤 이 파일을 실행한다.
# macOS의 install-autostart.sh가 tmux 세션에서 claude --channels를 실행하는 것과 동일한 역할이다.
#
# 환경변수(Windows 시스템 환경변수 또는 .env)에서 Discord 설정을 읽고,
# Claude Code CLI를 Discord channels 플러그인과 함께 실행한다.

[CmdletBinding()]
param(
    [string]$EnvFile = ""
)

$ErrorActionPreference = "Stop"

$ProjectRoot = Split-Path -Parent $PSScriptRoot
$EnvPath = if ($EnvFile) { $EnvFile } else { Join-Path $ProjectRoot ".env" }

# ── 재발 방지: 시작 전 좀비 락 자동 정리 ──────────────────────────
# Discord 플러그인 .in_use 디렉터리에서 죽은 PID 락 파일을 자동 삭제한다.
# claude.exe가 비정상 종료되면 락 파일이 남아 좀비가 되어 다음 실행을 방해한다.
$InUseDir = Join-Path $env:USERPROFILE ".claude\plugins\cache\claude-plugins-official\discord\0.0.4\.in_use"
if (Test-Path -LiteralPath $InUseDir) {
    $removedLocks = @()
    Get-ChildItem -LiteralPath $InUseDir -File | ForEach-Object {
        $lockFile = $_.FullName
        $lockPid = 0
        try {
            $lockData = Get-Content -LiteralPath $lockFile -Raw -ErrorAction Stop | ConvertFrom-Json
            $lockPid = [int]$lockData.pid
        } catch {
            # JSON이 아니거나 읽을 수 없으면 파일 이름을 PID로 시도
            [int]::TryParse($_.Name, [ref]$lockPid) | Out-Null
        }
        if ($lockPid -gt 0) {
            $proc = Get-Process -Id $lockPid -ErrorAction SilentlyContinue
            if (-not $proc) {
                Remove-Item -LiteralPath $lockFile -Force -ErrorAction SilentlyContinue
                $removedLocks += $lockPid
            }
        }
    }
    if ($removedLocks.Count -gt 0) {
        Write-Host "[CLEAN] 좀비 락 $($removedLocks.Count)개 삭제: $($removedLocks -join ', ')" -ForegroundColor Yellow
    }
}

# ── 재발 방지: 중복 실행 가드 ─────────────────────────────────────
# 이미 claude.exe --channels가 실행 중이면 새로 실행하지 않는다.
$runningClaude = Get-Process -Name claude -ErrorAction SilentlyContinue | Where-Object {
    try {
        (Get-CimInstance Win32_Process -Filter "ProcessId=$($_.Id)").CommandLine -match "channels"
    } catch { $false }
}
if ($runningClaude) {
    $runningCount = @($runningClaude).Count
    Write-Host "[GUARD] 이미 claude.exe --channels가 $runningCount개 실행 중입니다." -ForegroundColor Yellow
    Write-Host "        PID: $($runningClaude.Id -join ', ')" -ForegroundColor Yellow
    Write-Host "        새 인스턴스를 시작하지 않고 종료합니다." -ForegroundColor Yellow
    Write-Host "        재시작하려면 먼저 기존 프로세스를 종료하세요." -ForegroundColor Cyan
    exit 0
}

# .env 파일이 있으면 읽어서 세션 환경변수로 로드 (이미 시스템 환경변수가 있으면 덮어쓰지 않음)
if (Test-Path -LiteralPath $EnvPath) {
    $envKeys = @(
        "WORK_CHANNEL_ID",
        "CHAT_CHANNEL_ID",
        "APPROVER_USER_ID",
        "ORCH_BOT_TOKEN",
        "CLAUDE_BOT_TOKEN",
        "CODEX_BOT_TOKEN",
        "GEMINI_BOT_TOKEN"
    )
    foreach ($rawLine in Get-Content -LiteralPath $EnvPath -Encoding utf8) {
        $line = $rawLine.Trim()
        if (-not $line -or $line.StartsWith("#")) { continue }
        $separator = $line.IndexOf("=")
        if ($separator -lt 1) { continue }
        $key = $line.Substring(0, $separator).Trim()
        $value = $line.Substring($separator + 1).Trim().Trim('"').Trim("'")
        if ($envKeys -contains $key -and -not [Environment]::GetEnvironmentVariable($key, "Process")) {
            [Environment]::SetEnvironmentVariable($key, $value, "Process")
        }
    }
    Write-Host "[INFO] .env 로드 완료: $EnvPath"
}

# 필수 환경변수 확인
$requiredKeys = @("WORK_CHANNEL_ID", "CLAUDE_BOT_TOKEN", "CODEX_BOT_TOKEN", "GEMINI_BOT_TOKEN")
$missing = @()
foreach ($key in $requiredKeys) {
    $val = [Environment]::GetEnvironmentVariable($key, "Process")
    if (-not $val) {
        $missing += $key
    }
}
if ($missing.Count -gt 0) {
    Write-Host "[ERROR] 필수 환경변수가 누락되었습니다: $($missing -join ', ')" -ForegroundColor Red
    Write-Host "        .env 파일을 생성하거나 Windows 시스템 환경변수에 설정하세요." -ForegroundColor Yellow
    exit 1
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  GY Discord Multi-Agent Orchestrator" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  프로젝트: $ProjectRoot"
Write-Host "  작업 채널: $env:WORK_CHANNEL_ID"
Write-Host "  수다 채널: $env:CHAT_CHANNEL_ID"
Write-Host "  승인자 ID: $env:APPROVER_USER_ID"
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Claude Code CLI 확인
$claudeCmd = Get-Command claude -ErrorAction SilentlyContinue
if (-not $claudeCmd) {
    $claudePath = Join-Path $env:USERPROFILE ".claude\bin\claude.exe"
    if (Test-Path $claudePath) {
        $claudeCmd = [PSCustomObject]@{ Source = $claudePath }
    } else {
        Write-Host "[ERROR] Claude Code CLI를 찾을 수 없습니다." -ForegroundColor Red
        Write-Host "        npm install -g @anthropic-ai/claude-code 로 설치하세요." -ForegroundColor Yellow
        exit 1
    }
}

Write-Host "[INFO] Claude Code CLI: $($claudeCmd.Source)" -ForegroundColor Green
Write-Host "[INFO] Discord channels 플러그인으로 오케스트레이터를 시작합니다..." -ForegroundColor Green
Write-Host ""

# Claude Code를 Discord channels 플러그인과 함께 실행
# ai-runner.py 래퍼(subprocess.run)는 stdin 파이프를 연결하지 않아
# Discord 플러그인 메시지가 Claude Code에 전달되지 않음
# → claude.exe를 직접 호출하여 stdin/stdout/stderr를 터미널에 직접 연결
# ── orchestrator_web.py 백그라운드 기동 (폰 원격 관리 UI) ──────────
# 포트 8865에서 이미 실행 중이면 중복 실행하지 않는다.
$webPyPath = Join-Path $ProjectRoot "orchestrator_web.py"
if (Test-Path -LiteralPath $webPyPath) {
    $webPort = 8870
    $portInUse = Get-NetTCPConnection -LocalPort $webPort -State Listen -ErrorAction SilentlyContinue
    if ($portInUse) {
        Write-Host "[GUARD] orchestrator_web.py가 이미 포트 $webPort에서 실행 중 (PID: $($portInUse.OwningProcess -join ', '))" -ForegroundColor Yellow
    } else {
        Write-Host "[INFO] orchestrator_web.py 백그라운드 시작 (포트 $webPort)..." -ForegroundColor Green
        $pythonExe = (Get-Command python -ErrorAction SilentlyContinue)?.Source
        if (-not $pythonExe) {
            $pythonExe = (Get-Command python3 -ErrorAction SilentlyContinue)?.Source
        }
        if ($pythonExe) {
            Start-Process -FilePath $pythonExe `
                -ArgumentList $webPyPath `
                -WorkingDirectory $ProjectRoot `
                -WindowStyle Hidden `
                -PassThru | ForEach-Object {
                    Write-Host "[INFO] orchestrator_web.py PID=$($_.Id)" -ForegroundColor Green
                }
        } else {
            Write-Host "[WARN] python을 찾을 수 없어 web.py를 시작하지 않습니다." -ForegroundColor Yellow
        }
    }
} else {
    Write-Host "[WARN] orchestrator_web.py를 찾을 수 없습니다: $webPyPath" -ForegroundColor Yellow
}

Set-Location $ProjectRoot
$claudeExe = "C:\nvm4w\nodejs\node_modules\@anthropic-ai\claude-code\bin\claude.exe"
if (Test-Path $claudeExe) {
    Write-Host "[INFO] Claude Code 백그라운드 실행: $claudeExe" -ForegroundColor Green
        # --print(-p) 모드로 백그라운드 실행 (codex exec 방식과 동일 — stdin으로 프롬프트 전달)
        "Discord channels ready" | & $claudeExe -p --channels "plugin:discord@claude-plugins-official"
} else {
    $claudeDirect = "C:\nvm4w\nodejs\claude.cmd"
    if (Test-Path $claudeDirect) {
        Write-Host "[INFO] nvm4w claude.cmd 호출: $claudeDirect" -ForegroundColor Green
        & $claudeDirect --channels "plugin:discord@claude-plugins-official"
    } else {
        Write-Host "[INFO] 기본 경로 사용: $($claudeCmd.Source)" -ForegroundColor Yellow
        & $claudeCmd.Source --channels "plugin:discord@claude-plugins-official"
    }
}
