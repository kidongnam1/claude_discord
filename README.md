# Claude Discord Multi-Agent Orchestrator

[![Validate](https://github.com/kidongnam1/claude_discord/actions/workflows/validate.yml/badge.svg)](https://github.com/kidongnam1/claude_discord/actions/workflows/validate.yml)

Claude Code를 Discord의 오케스트레이터로 사용하고, Claude·Codex·Gemini 워커가 각자의 봇 이름으로 작업 진행 상황을 게시하도록 돕는 운영 템플릿입니다.

현재 버전: `v1.1.0`

## 주요 기능

- 작업 채널에 Discord 공개 스레드 생성
- Claude·Codex·Gemini 봇 계정별 메시지 게시
- 승인자 ID를 기준으로 작업 승인 통제
- 태스크, 워커 지시서, 결과, 운영 로그 템플릿 제공
- macOS 로그인 시 Claude Code 오케스트레이터 자동 실행
- 실제 Discord 요청 없이 확인할 수 있는 `DRY_RUN` 모드
- Codex에서 채널 확인·최근 메시지 조회·역할별 전송을 제공하는 로컬 Discord MCP
- Windows PowerShell 연결 및 실전송 검사

## 요구 사항

- Windows 10/11 또는 macOS
- Bash, `curl`, Python 3
- Node.js 22 이상
- `tmux`
- Claude Code와 Discord 채널 플러그인
- Discord 봇 4개와 각 봇 토큰

## 설치

자동 시작 스크립트는 프로젝트 경로를 `$HOME/discord-multiagent`로 사용합니다.

```bash
git clone https://github.com/kidongnam1/claude_discord.git "$HOME/discord-multiagent"
cd "$HOME/discord-multiagent"
cp .env.example .env
chmod +x scripts/*.sh
```

`.env`에 실제 Discord ID와 봇 토큰을 입력합니다.

```dotenv
WORK_CHANNEL_ID=
CHAT_CHANNEL_ID=
APPROVER_USER_ID=

ORCH_BOT_TOKEN=
CLAUDE_BOT_TOKEN=
CODEX_BOT_TOKEN=
GEMINI_BOT_TOKEN=
```

`.env`는 Git에서 제외됩니다. 토큰을 문서, 채팅, 커밋에 붙여 넣지 마세요.
값은 반드시 `KEY=값`처럼 등호 바로 뒤에 입력합니다. `KEY=    값`처럼 공백을 넣으면 Bash가 값을 명령으로 오인할 수 있습니다.
별도 오케스트레이터 봇을 사용하지 않는 경우 `ORCH_BOT_TOKEN`은 비워둘 수 있으며, 스레드 생성에는 Claude 봇 토큰이 사용됩니다.
REST 스크립트와 MCP는 `.env`를 셸 코드로 실행하지 않고 허용된 설정 이름만 데이터로 읽습니다.

## Codex Discord MCP

의존성을 설치합니다.

```powershell
npm install
```

Codex `config.toml`에 다음 서버를 등록하면 새 Codex 세션부터 Discord 도구를 사용할 수 있습니다.

```toml
[mcp_servers.discord]
enabled = true
command = "node"
args = ['D:\program-kdn\claude_discord\mcp\discord-mcp.mjs']
startup_timeout_sec = 30
```

제공 도구:

- `discord_connection_status`: 세 봇과 기본 채널 연결 확인
- `discord_list_messages`: 최근 메시지 최대 25개 조회
- `discord_send_message`: Claude·Codex·Gemini 역할별 메시지 전송
- `discord_create_thread`: 작업 채널에 공개 스레드 생성

모든 메시지 전송은 멘션을 비활성화합니다. 토큰은 `.env`에서만 읽고 MCP 결과에는 반환하지 않습니다.
채널 조회·전송은 `.env`의 `WORK_CHANNEL_ID`와 `CHAT_CHANNEL_ID`로 제한되며, 스레드 생성은 작업 채널에서만 허용됩니다.

## Windows 연결 검사

읽기 전용 연결 검사:

```powershell
.\scripts\Test-DiscordConnection.ps1
```

세 봇이 테스트 메시지를 각각 한 건씩 보내는 실제 검사:

```powershell
.\scripts\Test-DiscordConnection.ps1 -SendLiveTest
```

## 안전한 사전검사

실제 Discord에 요청을 보내기 전에 DRY-RUN으로 요청 내용을 확인합니다.

```bash
DRY_RUN=1 ./scripts/new-thread.sh "첫 작업"
DRY_RUN=1 ./scripts/post-as.sh claude 123456789012345678 "작업을 시작합니다"
```

## 사용법

### 작업 스레드 생성

```bash
THREAD_ID=$(./scripts/new-thread.sh "재고 프로그램 점검")
echo "$THREAD_ID"
```

### 워커 이름으로 메시지 게시

```bash
./scripts/post-as.sh claude "$THREAD_ID" "설계를 시작합니다"
./scripts/post-as.sh codex "$THREAD_ID" "코드 검증을 시작합니다"
./scripts/post-as.sh gemini "$THREAD_ID" "자료 조사를 시작합니다"
```

허용되는 워커 이름은 `claude`, `codex`, `gemini`입니다. Discord 멘션은 기본적으로 비활성화됩니다.

## macOS 자동 시작

프로젝트를 `$HOME/discord-multiagent`에 설치한 뒤 실행합니다.

```bash
./scripts/install-autostart.sh
```

확인:

```bash
launchctl list | grep com.discord-multiagent.orchestrator
tmux attach -t orchestrator
```

해제:

```bash
launchctl unload "$HOME/Library/LaunchAgents/com.discord-multiagent.orchestrator.plist"
```

## 디렉터리 구조

```text
.
├── CLAUDE.md                 # 오케스트레이터 운영 지침
├── VERSION                   # 프로그램 버전
├── _shared/                  # 워커 간 공유 파일
├── _templates/               # 태스크·지시서·결과·로그 템플릿
├── scripts/
│   ├── install-autostart.sh  # macOS 자동 시작 등록
│   ├── new-thread.sh         # Discord 스레드 생성
│   ├── post-as.sh            # 워커 봇 메시지 게시
│   └── validate.sh           # 로컬·CI 공통 검사
└── tasks/                    # 작업별 정본 저장 위치
```

## 자동검사

GitHub Actions는 push와 pull request마다 다음 항목을 확인합니다.

- Bash 문법
- 셸 스크립트 실행 권한
- 버전 형식과 릴리스 태그 일치
- `.env` 제외 규칙
- 스레드 생성과 메시지 게시 DRY-RUN

같은 검사를 로컬에서 실행할 수 있습니다.

```bash
./scripts/validate.sh
```

## 보안 원칙

- 실제 토큰은 `.env` 또는 별도 비밀 저장소에서만 관리합니다.
- `.env`, `.env.test`, `.discord-state/`는 커밋하지 않습니다.
- 승인자 ID와 일치하는 사람의 승인만 유효합니다.
- 봇이나 웹훅의 승인 메시지는 무시합니다.
- DRY-RUN 출력에도 실제 토큰을 표시하지 않습니다.
