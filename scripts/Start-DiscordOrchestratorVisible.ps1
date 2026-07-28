$ErrorActionPreference = "Stop"

$projectRoot = Split-Path -Parent $PSScriptRoot
$launcher = Join-Path $projectRoot ".discord-state\Start-DiscordOrchestrator.ps1"
$windowsTerminal = Join-Path $env:LOCALAPPDATA "Microsoft\WindowsApps\wt.exe"

if (-not (Test-Path -LiteralPath $launcher)) {
    throw "Discord Orchestrator launcher was not found."
}

if (-not (Test-Path -LiteralPath $windowsTerminal)) {
    throw "Windows Terminal was not found."
}

$terminalArguments = @(
    "-w"
    "new"
    "new-tab"
    "--title"
    "`"GY Discord Orchestrator - Claude Channels`""
    "--suppressApplicationTitle"
    "pwsh.exe"
    "-NoProfile"
    "-ExecutionPolicy"
    "Bypass"
    "-File"
    "`"$launcher`""
)

Start-Process `
    -FilePath $windowsTerminal `
    -ArgumentList $terminalArguments `
    -WorkingDirectory $projectRoot `
    -WindowStyle Normal
