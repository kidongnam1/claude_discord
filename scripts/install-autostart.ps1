# install-autostart.ps1 — Windows 로그인 시 오케스트레이터를 자동 기동한다.
#
# 사용법: .\scripts\install-autostart.ps1
#
# - Windows 작업스케줄러에 로그인 시 실행 태스크를 등록한다
# - 기존에 등록된 태스크가 있으면 먼저 삭제 후 재등록한다
# - Start-DiscordOrchestratorVisible.ps1을 실행하여 Windows Terminal에서 오케스트레이터를 띤다
# - 관리자 권한이 필요하지 않다 (현재 사용자 컨텍스트로 실행)

[CmdletBinding()]
param(
    [string]$TaskName = "GYDiscordOrchestrator"
)

$ErrorActionPreference = "Stop"

$ProjectRoot = Split-Path -Parent $PSScriptRoot
$Launcher = Join-Path $PSScriptRoot "Start-DiscordOrchestratorVisible.ps1"

if (-not (Test-Path -LiteralPath $Launcher)) {
    throw "Start-DiscordOrchestratorVisible.ps1을 찾을 수 없습니다: $Launcher"
}

# 기존 태스크가 있으면 삭제
$existingTask = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
if ($existingTask) {
    Write-Host "기존 작업스케줄러 태스크 삭제 중: $TaskName"
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
}

# 작업스케줄러 액션: PowerShell에서 런처 스크립트 실행
$action = New-ScheduledTaskAction `
    -Execute "powershell.exe" `
    -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$Launcher`"" `
    -WorkingDirectory $ProjectRoot

# 트리거: 사용자 로그인 시
$trigger = New-ScheduledTaskTrigger -AtLogOn

# 설정: 실행 중이면 새 인스턴스 시작하지 않음, 실패 시 1분 간격 3회 재시도
$settings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -StartWhenAvailable `
    -RestartCount 3 `
    -RestartInterval (New-TimeSpan -Minutes 1)

# 현재 사용자 컨텍스트로 실행 (관리자 권한 불필요)
$principal = New-ScheduledTaskPrincipal `
    -UserId $env:USERNAME `
    -LogonType Interactive `
    -RunLevel Limited

Register-ScheduledTask `
    -TaskName $TaskName `
    -Action $action `
    -Trigger $trigger `
    -Settings $settings `
    -Principal $principal `
    -Description "GY Discord Multi-Agent Orchestrator - 로그인 시 자동 실행" | Out-Null

Write-Host ""
Write-Host "=== Windows 자동 기동 설정 완료 ==="
Write-Host ""
Write-Host "  태스크 이름: $TaskName"
Write-Host "  프로젝트:   $ProjectRoot"
Write-Host "  런처:       $Launcher"
Write-Host ""
Write-Host "확인 방법:"
Write-Host "  Get-ScheduledTask -TaskName '$TaskName'"
Write-Host "  Start-ScheduledTask -TaskName '$TaskName'"
Write-Host ""
Write-Host "해제 방법:"
Write-Host "  Unregister-ScheduledTask -TaskName '$TaskName' -Confirm:`$false"
Write-Host ""
