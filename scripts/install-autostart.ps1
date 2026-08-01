# install-autostart.ps1 — Windows 로그인 시 오케스트레이터를 자동 기동한다.
# 사용법: .\scripts\install-autostart.ps1
# 시작 프로그램 폴더에 바로가기를 생성한다 (관리자 권한 불필요).

[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"

$ProjectRoot = Split-Path -Parent $PSScriptRoot
$Launcher = Join-Path $PSScriptRoot "Start-DiscordOrchestratorVisible.ps1"
$ShortcutName = "GY Discord Orchestrator.lnk"
$StartupFolder = [Environment]::GetFolderPath("Startup")
$ShortcutPath = Join-Path $StartupFolder $ShortcutName

if (-not (Test-Path -LiteralPath $Launcher)) {
    throw "Start-DiscordOrchestratorVisible.ps1을 찾을 수 없습니다: $Launcher"
}

# 기존 바로가기 삭제
if (Test-Path -LiteralPath $ShortcutPath) {
    Write-Host "기존 시작 프로그램 바로가기 삭제 중..."
    Remove-Item -LiteralPath $ShortcutPath -Force
}

# WScript.Shell COM 객체로 바로가기 생성
$shell = New-Object -ComObject WScript.Shell
$shortcut = $shell.CreateShortcut($ShortcutPath)
$shortcut.TargetPath = "powershell.exe"
$shortcut.Arguments = '-NoProfile -ExecutionPolicy Bypass -File "' + $Launcher + '"'
$shortcut.WorkingDirectory = $ProjectRoot
$shortcut.WindowStyle = 1
$shortcut.Description = "GY Discord Multi-Agent Orchestrator"
$shortcut.IconLocation = "powershell.exe,0"
$shortcut.Save()

Write-Host ""
Write-Host "=== Windows 자동 기동 설정 완료 ==="
Write-Host ""
Write-Host "  바로가기:   $ShortcutPath"
Write-Host "  프로젝트:   $ProjectRoot"
Write-Host "  런처:       $Launcher"
Write-Host ""
Write-Host "확인 방법:"
Write-Host "  시작 프로그램 폴더 열기: shell:startup"
Write-Host "  또는: Get-ChildItem '$StartupFolder'"
Write-Host ""
Write-Host "해제 방법:"
Write-Host "  Remove-Item '$ShortcutPath' -Force"
Write-Host ""
