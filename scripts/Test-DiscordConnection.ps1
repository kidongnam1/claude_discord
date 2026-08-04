[CmdletBinding()]
param(
    [string]$EnvFile = (Join-Path (Split-Path $PSScriptRoot -Parent) ".env"),
    [switch]$SendLiveTest
)

$ErrorActionPreference = "Stop"
$DiscordApi = "https://discord.com/api/v10"

function Read-DotEnv {
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        throw ".env 파일을 찾을 수 없습니다: $Path"
    }

    $values = @{}
    foreach ($rawLine in Get-Content -LiteralPath $Path -Encoding utf8) {
        $line = $rawLine.Trim()
        if (-not $line -or $line.StartsWith("#")) { continue }
        $separator = $line.IndexOf("=")
        if ($separator -lt 1) { continue }
        $key = $line.Substring(0, $separator).Trim()
        $value = $line.Substring($separator + 1).Trim().Trim('"').Trim("'")
        $values[$key] = $value
    }
    return $values
}

function Invoke-Discord {
    param(
        [Parameter(Mandatory)][string]$Token,
        [Parameter(Mandatory)][string]$Method,
        [Parameter(Mandatory)][string]$Endpoint,
        [hashtable]$Body
    )

    $headers = @{
        Authorization = "Bot $Token"
        "User-Agent" = "DiscordBot (https://github.com/kidongnam1/claude_discord, 1.2.0)"
    }
    $parameters = @{
        Uri = "$DiscordApi$Endpoint"
        Method = $Method
        Headers = $headers
        ContentType = "application/json; charset=utf-8"
    }
    if ($null -ne $Body) {
        $parameters.Body = $Body | ConvertTo-Json -Depth 5 -Compress
    }
    Invoke-RestMethod @parameters
}

$config = Read-DotEnv -Path $EnvFile
$channelId = if ($config.CHAT_CHANNEL_ID) { $config.CHAT_CHANNEL_ID } else { $config.WORK_CHANNEL_ID }
if ($channelId -notmatch "^\d{17,20}$") {
    throw "CHAT_CHANNEL_ID 또는 WORK_CHANNEL_ID가 올바른 Discord ID가 아닙니다."
}

$roles = [ordered]@{
    claude = "CLAUDE_BOT_TOKEN"
    codex = "CODEX_BOT_TOKEN"
    gemini = "GEMINI_BOT_TOKEN"
}

$results = @()
foreach ($entry in $roles.GetEnumerator()) {
    $token = $config[$entry.Value]
    if (-not $token) {
        $results += [pscustomobject]@{ Role = $entry.Key; Bot = ""; Channel = ""; Status = "TOKEN_MISSING" }
        continue
    }
    try {
        $bot = Invoke-Discord -Token $token -Method Get -Endpoint "/users/@me"
        $channel = Invoke-Discord -Token $token -Method Get -Endpoint "/channels/$channelId"
        $status = "CONNECTED"
        if ($SendLiveTest) {
            $payload = @{
                content = "[$($entry.Key.ToUpper())] GY Discord 통합 연결 테스트 성공 · $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') KST"
                allowed_mentions = @{ parse = @() }
            }
            $message = Invoke-Discord -Token $token -Method Post -Endpoint "/channels/$channelId/messages" -Body $payload
            $status = "SENT:$($message.id)"
        }
        $results += [pscustomobject]@{
            Role = $entry.Key
            Bot = $bot.username
            Channel = $channel.name
            Status = $status
        }
    }
    catch {
        $safeError = $_.Exception.Message -replace [regex]::Escape($token), "[REDACTED]"
        $results += [pscustomobject]@{
            Role = $entry.Key
            Bot = ""
            Channel = ""
            Status = "FAILED: $safeError"
        }
    }
}

$results | Format-Table -AutoSize
if ($results.Status -match "^FAILED|TOKEN_MISSING") {
    exit 1
}
