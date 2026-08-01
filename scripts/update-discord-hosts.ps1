# update-discord-hosts.ps1 — Discord 도메인 hosts 파일 자동 업데이트
#
# 사용법: 관리자 PowerShell에서 실행
#   .\update-discord-hosts.ps1
#
# Discord Cloudflare CDN IP는 변경될 수 있으므로,
# 주기적으로 Google DNS(8.8.8.8)에서 최신 IP를 조회해서 hosts 파일을 업데이트한다.
# 작업 스케줄러에 등록하면 주 1회 자동 실행 가능.

$ErrorActionPreference = "Stop"

$HostsPath = "C:\Windows\System32\drivers\etc\hosts"
$DiscordDomains = @("gateway.discord.gg", "discord.com", "cdn.discordapp.com")
$Marker = "# Discord DNS bypass (auto-updated)"

Write-Host ""
Write-Host "=== Discord hosts 자동 업데이트 ===" -ForegroundColor Cyan
Write-Host ""

# 1. 기존 Discord 항목 제거
Write-Host "[1/3] 기존 Discord hosts 항목 제거 중..." -ForegroundColor Yellow
$content = Get-Content $HostsPath -Encoding utf8
$newContent = $content | Where-Object {
    $_ -notmatch "discord\.gg|discord\.com|discordapp\.com|Discord DNS bypass" -and
    $_ -notmatch "^# Discord DNS bypass"
}
$newContent | Set-Content $HostsPath -Encoding utf8
Write-Host "  [OK] 기존 항목 제거 완료" -ForegroundColor Green

# 2. Google DNS에서 최신 IP 조회
Write-Host ""
Write-Host "[2/3] Google DNS에서 Discord 최신 IP 조회 중..." -ForegroundColor Yellow
$entries = @($Marker)
foreach ($domain in $DiscordDomains) {
    $result = nslookup $domain 8.8.8.8 2>&1
    $ip = ($result | Select-String "Address" | Select-Object -Last 1).ToString().Split()[-1]
    if ($ip -and $ip -ne "8.8.8.8" -and $ip -notmatch "^10\.") {
        $entries += "$ip $domain"
        Write-Host "  [OK] $domain -> $ip" -ForegroundColor Green
    } else {
        Write-Host "  [SKIP] $domain -> $ip (유효하지 않음)" -ForegroundColor Yellow
    }
}

# 3. hosts 파일에 추가
Write-Host ""
Write-Host "[3/3] hosts 파일에 새 항목 추가 중..." -ForegroundColor Yellow
Add-Content -Path $HostsPath -Value "`n$($entries -join "`n")" -Encoding utf8
Write-Host "  [OK] hosts 파일 업데이트 완료" -ForegroundColor Green

# 4. DNS 캐시 플러시
Clear-DnsClientCache
Write-Host "  [OK] DNS 캐시 플러시 완료" -ForegroundColor Green

Write-Host ""
Write-Host "=== 완료 ===" -ForegroundColor Green
Write-Host "Discord hosts 항목이 최신 IP로 업데이트되었습니다." -ForegroundColor Green
Write-Host ""
