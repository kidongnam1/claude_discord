# fix-dns-gwangyang.ps1 — 광양PC DNS 하이재킹 점검 및 수정 스크립트
#
# 사용법: 관리자 PowerShell에서 실행
#   Set-ExecutionPolicy Bypass -Scope Process
#   .\fix-dns-gwangyang.ps1
#
# 이 스크립트는 다음을 수행한다:
# 1. 현재 DNS 서버 확인
# 2. 사내 DNS(10.0.1.61) 하이재킹 검사
# 3. DNS를 8.8.8.8 + 1.1.1.1로 변경
# 4. Discord 도메인 정상 해석 확인

$ErrorActionPreference = "Stop"

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  광양PC DNS 하이재킹 점검 및 수정" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# 1. 현재 DNS 서버 확인
Write-Host "[1/4] 현재 DNS 서버 확인 중..." -ForegroundColor Yellow
$adapters = Get-NetAdapter | Where-Object { $_.Status -eq 'Up' -and $_.Name -notmatch 'Tailscale|Loopback|vEthernet' }
foreach ($adapter in $adapters) {
    $dns = Get-DnsClientServerAddress -InterfaceAlias $adapter.Name -AddressFamily IPv4
    Write-Host "  어댑터: $($adapter.Name)" -ForegroundColor White
    Write-Host "  DNS 서버: $($dns.ServerAddresses -join ', ')" -ForegroundColor White
    
    # 하이재킹 검사
    $hijacked = $false
    foreach ($dnsServer in $dns.ServerAddresses) {
        if ($dnsServer -eq "10.0.1.61") {
            $hijacked = $true
            Write-Host "  [WARNING] 사내 DNS(10.0.1.61) 감지 — 하이재킹 위험!" -ForegroundColor Red
        }
    }
    
    if ($hijacked) {
        Write-Host ""
        Write-Host "  [2/4] Discord 도메인 하이재킹 검사..." -ForegroundColor Yellow
        $testDomains = @("gateway.discord.gg", "discord.com", "google.com")
        foreach ($domain in $testDomains) {
            $result = nslookup $domain 2>&1
            $ip = ($result | Select-String "Address" | Select-Object -Last 1).ToString().Split()[-1]
            if ($ip -eq "10.0.1.61") {
                Write-Host "  [HIJACK] $domain -> 10.0.1.61 (하이재킹됨)" -ForegroundColor Red
            } else {
                Write-Host "  [OK] $domain -> $ip" -ForegroundColor Green
            }
        }
        
        Write-Host ""
        Write-Host "  [3/4] DNS 서버를 8.8.8.8 + 1.1.1.1로 변경 중..." -ForegroundColor Yellow
        Set-DnsClientServerAddress -InterfaceAlias $adapter.Name -ServerAddresses ("8.8.8.8", "1.1.1.1") -Confirm:$false
        Clear-DnsClientCache
        Write-Host "  [OK] DNS 변경 완료 + 캐시 플러시" -ForegroundColor Green
        
        Write-Host ""
        Write-Host "  [4/4] 변경 후 검증..." -ForegroundColor Yellow
        Start-Sleep 2
        foreach ($domain in $testDomains) {
            $result = nslookup $domain 2>&1
            $ip = ($result | Select-String "Address" | Select-Object -Last 1).ToString().Split()[-1]
            if ($ip -eq "10.0.1.61") {
                Write-Host "  [FAIL] $domain -> $ip (여전히 하이재킹)" -ForegroundColor Red
            } else {
                Write-Host "  [OK] $domain -> $ip (정상)" -ForegroundColor Green
            }
        }
    } else {
        Write-Host "  [OK] 사내 DNS 없음 — 하이재킹 위험 없음" -ForegroundColor Green
    }
    Write-Host ""
}

Write-Host "========================================" -ForegroundColor Green
Write-Host "  DNS 점검 완료!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host ""
Write-Host "Discord 오케스트레이터가 설치된 경우:"
Write-Host "  claude.exe를 재시작해야 새 DNS가 적용됩니다."
Write-Host ""
