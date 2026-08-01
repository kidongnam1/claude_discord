# 로컬 설정 백업 가이드

이 폴더는 git에 올라가지 않는 로컬 설정 파일의 템플릿을 보관합니다.
광양 PC 등 다른 PC에서 설정할 때 참조하세요.

## 필수 로컬 설정 3곳

### 1. .env (프로젝트 루트)
- `setup-discord.ps1` 실행 또는 `.env.example` 복사하여 수동 생성
- 봇 토큰 3개 + 채널 ID 2개 + 승인자 ID 1개 입력
- git에 올라가지 않음 (.gitignore)

### 2. ~/.claude/channels/discord/.env
- Discord 플러그인이 읽는 토큰 파일
- 형식: `DISCORD_BOT_TOKEN=<CL-Worker 봇 토큰>`
- CL-Worker 토큰은 .env의 CLAUDE_BOT_TOKEN과 동일한 값

### 3. ~/.claude/channels/discord/access.json
- Discord 플러그인의 채널/사용자 허용 목록
- `access.json.example`을 참고하여 생성
- #작업, #수다 채널 ID와 승인자 ID 등록
- requireMention: false (봇 멘션 없이도 메시지 수신)

### 4. .discord-state/Start-DiscordOrchestrator.ps1
- Windows용 Claude Code 오케스트레이터 런처
- `Start-DiscordOrchestrator.ps1.example`을 참고하여 생성
- .env를 로드하고 `claude --channels plugin:discord@claude-plugins-official` 실행

## 필수 의존성

- **bun**: `npm install -g bun` (Discord 플러그인 실행)
- **Claude Code CLI**: `npm install -g @anthropic-ai/claude-code`
- **Node.js 22+**: MCP 서버 실행
- **Git Bash**: bash 스크립트 실행 (post-as.sh, new-thread.sh)

## 자동시작 (Windows)

```powershell
.\scripts\install-autostart.ps1
```

시작 프로그램 폴더에 바로가기 생성 (관리자 권한 불필요).