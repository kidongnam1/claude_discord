[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$projectDir = Split-Path -Parent $PSScriptRoot
$envPath = Join-Path $projectDir '.env'
$examplePath = Join-Path $projectDir '.env.example'

if (-not (Test-Path -LiteralPath $envPath)) {
    Copy-Item -LiteralPath $examplePath -Destination $envPath
}

$lines = [System.Collections.Generic.List[string]]::new()
$lines.AddRange([string[]](Get-Content -LiteralPath $envPath -Encoding UTF8))

function Get-CurrentValue([string]$Name) {
    foreach ($line in $lines) {
        if ($line -match ('^' + [regex]::Escape($Name) + '=(.*)$')) { return $Matches[1] }
    }
    return ''
}

function Set-EnvValue([string]$Name, [string]$Value) {
    for ($index = 0; $index -lt $lines.Count; $index++) {
        if ($lines[$index] -match ('^' + [regex]::Escape($Name) + '=')) {
            $lines[$index] = "$Name=$Value"
            return
        }
    }
    $lines.Add("$Name=$Value")
}

function Read-Value([string]$Name, [string]$Label, [switch]$Secret) {
    $current = Get-CurrentValue $Name
    if ($Secret) {
        $secure = Read-Host "$Label (비우면 기존 값 유지)" -AsSecureString
        $pointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
        try { $value = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer) }
        finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer) }
    } else {
        $suffix = if ($current) { " [$current]" } else { '' }
        $value = Read-Host "$Label$suffix"
    }
    if ([string]::IsNullOrWhiteSpace($value)) { return $current }
    return $value.Trim()
}

$token = Read-Value 'ROUTER_BOT_TOKEN' '새 GY-AI-Router 봇 토큰' -Secret
$guild = Read-Value 'ROUTER_GUILD_ID' 'Discord 서버 ID'
$users = Read-Value 'ROUTER_ALLOWED_USER_IDS' '허용 사용자 ID (쉼표 구분)'
$channels = Read-Value 'ROUTER_ALLOWED_CHANNEL_IDS' '허용 채널 ID (쉼표 구분)'
$repos = Read-Value 'ROUTER_ALLOWED_REPOS' '허용 저장소 절대 경로 (쉼표 구분)'
$defaultRepo = Read-Value 'ROUTER_DEFAULT_REPO' '기본 저장소 절대 경로'

Set-EnvValue 'ROUTER_BOT_TOKEN' $token
Set-EnvValue 'ROUTER_GUILD_ID' $guild
Set-EnvValue 'ROUTER_ALLOWED_USER_IDS' $users
Set-EnvValue 'ROUTER_ALLOWED_CHANNEL_IDS' $channels
Set-EnvValue 'ROUTER_ALLOWED_REPOS' $repos
Set-EnvValue 'ROUTER_DEFAULT_REPO' $defaultRepo

[System.IO.File]::WriteAllLines($envPath, $lines, [System.Text.UTF8Encoding]::new($false))
Write-Host '[OK] .env를 UTF-8(BOM 없음)으로 저장했습니다. 토큰은 화면에 표시하지 않았습니다.'
& (Get-Command node -ErrorAction Stop).Source (Join-Path $projectDir 'router\discord-ai-router.mjs') --check
