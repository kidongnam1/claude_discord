# 광양PC 방문 체크리스트 — Discord 오케스트레이터 + DNS 수정
# ============================================================
# 작성일: 2026-08-01
# 예상 소요시간: 10분
# ------------------------------------------------------------

## 사전 준비 (서울PC에서 미리 해둘 것)
- [x] git push 완료 (c369e28)
- [x] fix-dns-gwangyang.ps1 저장소에 포함됨
- [x] setup-gwangyang-discord.ps1 저장소에 포함됨

## 광양PC에서 실행 순서

### 1단계: 저장소 동기화 (2분)
```powershell
cd D:\program\claude_discord
git pull origin main
```
# 저장소가 없으면:
```powershell
git clone https://github.com/kidongnam1/claude_discord.git D:\program\claude_discord
cd D:\program\claude_discord
cp .env.example .env
# .env에 봇 토큰 입력 (서울PC와 동일한 토큰)
```

### 2단계: DNS 하이재킹 점검 및 수정 (1분)
```powershell
# 관리자 PowerShell 실행
Set-ExecutionPolicy Bypass -Scope Process
.\scripts\fix-dns-gwangyang.ps1
```
# 스크립트가 자동으로:
#   - 사내DNS(10.0.1.61) 하이재킹 감지
#   - DNS를 8.8.8.8 + 1.1.1.1로 변경
#   - Discord 도메인 정상 해석 검증

### 3단계: Discord 오케스트레이터 설정 (3분)
```powershell
# 처음 설치하는 경우만
.\scripts\setup-gwangyang-discord.ps1
```
# 스크립트가 자동으로:
#   - bun 설치
#   - ~/.claude/channels/discord/.env 생성 (Orchestrator 봇 토큰)
#   - access.json 생성
#   - 런처 배치 (.discord-state/Start-DiscordOrchestrator.ps1)
#   - 시작폴더 바로가기 등록

### 4단계: 오케스트레이터 실행 (1분)
```powershell
.\scripts\Start-DiscordOrchestratorVisible.ps1
```
# Windows Terminal이 열리고 Claude Code가 Discord 플러그인과 함께 실행

### 5단계: 검증 (3분)
- [ ] 폰 Discord #수다 채널에서 "테스트"라고 보내기
- [ ] 광양PC에서 Orchestrator 봇이 응답하는지 확인
- [ ] #작업 채널에서 스레드 생성되는지 확인
- [ ] .in_use 락이 1개인지 확인

## 주의사항
1. 관리자 PowerShell 필요 (우클릭 → 관리자 권한으로 실행)
2. .env의 봇 토큰은 서울PC와 동일한 Orchestrator 봇 토큰 사용
3. DNS 변경 후 반드시 claude.exe 재시작 필요
4. 광양PC도 사내DNS(10.0.1.61)를 사용 중이면 같은 하이재킹 문제 발생 가능
5. setup-gwangyang-discord.ps1은 ORCH 봇 토큰을 자동으로 읽어서 channels 플러그인에 설정
