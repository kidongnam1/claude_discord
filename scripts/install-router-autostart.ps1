[CmdletBinding()]
param(
    [string]$TaskName = 'GYDiscordAIRouter'
)

$ErrorActionPreference = 'Stop'
$projectDir = Split-Path -Parent $PSScriptRoot
$launcher = Join-Path $projectDir 'scripts\Start-DiscordAiRouter.ps1'
$checkScript = Join-Path $projectDir 'router\discord-ai-router.mjs'
$node = (Get-Command node -ErrorAction Stop).Source

& $node $checkScript --check
if ($LASTEXITCODE -ne 0) {
    throw '라우터 설정 검사에 실패했습니다.'
}

$powerShell = (Get-Command powershell.exe -ErrorAction Stop).Source
$arguments = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$launcher`""
$action = New-ScheduledTaskAction -Execute $powerShell -Argument $arguments -WorkingDirectory $projectDir
$trigger = New-ScheduledTaskTrigger -AtLogOn
$settings = New-ScheduledTaskSettingsSet -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1) -ExecutionTimeLimit (New-TimeSpan -Days 3650)

Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Settings $settings -Description 'GY Codex Antigravity Hermes Discord router' -Force | Out-Null
Write-Host "[OK] 작업 스케줄러 등록 완료: $TaskName"
