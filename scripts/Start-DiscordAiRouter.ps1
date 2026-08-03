[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$projectDir = Split-Path -Parent $PSScriptRoot
$entryPoint = Join-Path $projectDir 'router\discord-ai-router.mjs'
$envFile = Join-Path $projectDir '.env'

if (-not (Test-Path -LiteralPath $entryPoint)) {
    throw "라우터 파일이 없습니다: $entryPoint"
}
if (-not (Test-Path -LiteralPath $envFile)) {
    throw ".env 파일이 없습니다. .env.example을 복사한 뒤 ROUTER 설정을 입력하세요."
}

$node = Get-Command node -ErrorAction Stop
Set-Location -LiteralPath $projectDir
Write-Host "[GY-AI-Router] 시작: $projectDir"
& $node.Source $entryPoint
exit $LASTEXITCODE
