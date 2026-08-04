# Claude Discord Multi-Agent Orchestrator

[![Validate](https://github.com/kidongnam1/claude_discord/actions/workflows/validate.yml/badge.svg)](https://github.com/kidongnam1/claude_discord/actions/workflows/validate.yml)

Claude Code를 Discord의 오케스트레이터로 사용하고, Claude·Codex·Gemini 워커가 각자의 봇 이름으로 작업 진행 상황을 게시하도록 돕는 운영 템플릿입니다.

현재 버전: `v1.2.0`

## 주요 기능

- 작업 채널에 Discord 공개 스레드 생성
- Claude·Codex·Gemini 봇 계정별 메시지 게시
- 승인자 ID를 기준으로 작업 승인 통제
- 태스크, 워커 지시서, 결과, 운영 로그 템플릿 제공
- macOS 로그인 시 Claude Code 오케스트레이터 자동 실행
- 실제 Discord 요청 없이 확인할 수 있는 `DRY_RUN` 모드
- Codex에서 채널 확인·최근 메시지 조회·역할별 전송을 제공하는 로컬 Discord MCP
- Windows PowerShell 연결 및 실전송 검사
- 하나의 전용 Discord 봇에서 Codex·Antigravity·Hermes CLI 작업 실행
- 읽기 작업 자동 실행, 쓰기 작업 `/approve` 승인, `/stop` 중지, 상태 영구 저장

## 요구 사항

- Windows 10/11 또는 macOS
- Bash, `curl`, Python 3
- Node.js 22 이상
- `tmux`
- Claude Code와 Discord 채널 플러그인
- Discord 봇 4개와 각 봇 토큰
- AI 라우터를 사용할 경우 별도의 `GY-AI-Router` Discord 봇 1개

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
Windows 시스템 환경변수에 직접 설정해도 동작합니다 (환경변수가 `.env` 파일보다 우선합니다).
값은 반드시 `KEY=값`처럼 등호 바로 뒤에 입력합니다. `KEY=    값`처럼 공백을 넣으면 Bash가 값을 명령으로 오인할 수 있습니다.
별도 오케스트레이터 봇을 사용하지 않는 경우 `ORCH_BOT_TOKEN`은 비워둘 수 있으며, 스레드 생성에는 Claude 봇 토큰이 사용됩니다.
REST 스크립트와 MCP는 `.env`를 셸 코드로 실행하지 않고 허용된 설정 이름만 데이터로 읽습니다.

## Codex·Antigravity·Hermes Discord 라우터

기존 Claude Discord 연결은 그대로 유지합니다. 별도의 `GY-AI-Router` 봇 하나가 다음 슬래시 명령을 담당합니다.

- `/codex`, `/agy`, `/hermes`: AI 선택 및 작업 요청
- `mode:read`: 바로 실행. Codex는 read-only, Antigravity는 plan, Hermes는 로컬 도구 차단
- `mode:write`: `pending_approval`로 저장한 뒤 `/approve job:작업ID`가 있어야 실행
- `/status`: 최근 작업 또는 지정 작업 상태 확인
- `/stop`: 실행 중인 프로세스와 자식 프로세스 중지

작업 상태와 로그는 Git에서 제외된 `.discord-router/`에 저장되므로 프로그램 재시작 후에도 남습니다. 저장소는 `ROUTER_ALLOWED_REPOS`에 정확히 등록된 루트만 허용합니다.

### 1. Discord 봇 준비

Discord Developer Portal에서 새 애플리케이션과 봇을 만들고 서버에 초대합니다. 권한은 `View Channels`, `Send Messages`, `Use Application Commands`만 부여합니다. 기존 Claude/워커 봇 토큰은 재사용하지 않습니다.

### 2. 라우터 설정

```powershell
.\scripts\setup-router.ps1
```

토큰은 보안 입력으로 받고 화면에 표시하지 않습니다. 직접 설정할 경우 다음 값을 `.env`에 추가합니다.

```dotenv
ROUTER_BOT_TOKEN=
ROUTER_GUILD_ID=
ROUTER_ALLOWED_USER_IDS=
ROUTER_ALLOWED_CHANNEL_IDS=
ROUTER_ALLOWED_REPOS=D:\program\claude_discord,D:\program\SQM_inventory
ROUTER_DEFAULT_REPO=D:\program\claude_discord
ROUTER_TIMEOUT_MINUTES=30
```

설정 검사와 실행:

```powershell
npm run router:check
npm run router:start
```

Windows 로그인 시 자동 시작 등록은 실제 Discord 실행 검증 후 진행합니다.

```powershell
.\scripts\install-router-autostart.ps1
```

Hermes는 원샷 모드 자체가 내부 승인 질문을 건너뛰므로, 읽기 모드에서는 로컬 파일·터미널 도구를 제공하지 않습니다. Hermes가 실제 저장소 파일을 읽거나 수정해야 하는 요청은 `mode:write`와 `/approve`를 사용합니다.

### VS Code 작업 영역

`GY-Discord-Router.code-workspace`를 열면 프로젝트 루트와 PowerShell 터미널이 기본으로 설정됩니다.

VS Code에서 `터미널 → 작업 실행`을 선택한 뒤 다음 작업을 사용할 수 있습니다.

- `GY Router: 최초 설정`
- `GY Router: 설정 검사`
- `GY Router: 실행` — 라우터 전용 터미널 사용
- `GY Router: 전체 테스트`

Discord 실전 연결이 성공하기 전에는 라우터 자동 시작 작업을 등록하지 않습니다.

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

## Windows 자동 시작

Windows 작업스케줄러에 로그인 시 자동 실행을 등록합니다.

```powershell
.\scripts\install-autostart.ps1
```

확인:

```powershell
Get-ScheduledTask -TaskName 'GYDiscordOrchestrator'
Start-ScheduledTask -TaskName 'GYDiscordOrchestrator'
```

해제:

```powershell
Unregister-ScheduledTask -TaskName 'GYDiscordOrchestrator' -Confirm:$false
```

### 설정 마법사 (최초 설정)

7개 값을 순서대로 묻고 .env를 자동 생성합니다. 채널 ID와 승인자 ID는 기본값이 미리 채워져 있습니다.

```powershell
.\scripts\setup-discord.ps1
```

- 기존 .env가 있으면 현재 값을 기본값으로 보여줍니다 (Enter로 유지)
- 봇 토큰은 입력값을 화면에 다시 출력하지 않습니다
- 완료 후 DRY_RUN 테스트를 자동 실행합니다

### 오케스트레이터 런처 (.discord-state)

`Start-DiscordOrchestratorVisible.ps1`은 `.discord-state\Start-DiscordOrchestrator.ps1`을 호출합니다.
이 디렉터리는 `.gitignore`에 포함되어 있으므로 각 PC에서 처음 실행 전 생성해야 합니다.

```powershell
# .discord-state 디렉터리가 없으면 생성
mkdir .discord-state -Force
# Claude Code CLI를 Discord channels 플러그인과 함께 실행하는 런처를 배치
# (macOS의 install-autostart.sh가 tmux에서 claude --channels를 실행하는 것과 동일)
```

런처는 다음을 수행합니다:
1. `.env` 파일이 있으면 로드 (시스템 환경변수가 이미 있으면 덮어쓰지 않음)
2. 필수 환경변수 확인
3. `claude --channels plugin:discord@claude-plugins-official` 실행

## 디렉터리 구조

```text
.
├── CLAUDE.md                 # 오케스트레이터 운영 지침
├── VERSION                   # 프로그램 버전
├── _shared/                  # 워커 간 공유 파일
├── _templates/               # 태스크·지시서·결과·로그 템플릿
├── scripts/
│   ├── install-autostart.sh  # macOS 자동 시작 등록
│   ├── install-autostart.ps1 # Windows 작업스케줄러 자동 시작 등록
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

## 2026-08-01 업데이트: DNS 하이재킹 해결 + 재발 방지

### 문제 및 해결
- **문제**: 사내 DNS(10.0.1.61)가 모든 외부 도메인을 내부 IP로 하이재킹 → Discord Gateway 연결 실패
- **해결**: "이더넷 2" DNS를 8.8.8.8 + 1.1.1.1로 영구 변경
- **좀비 락**: 과거 경로 중복 실행으로 .in_use 락 13개 누적 → 런처에 자동 정리+중복 가드 추가
- **ORCH 봇**: 지휘자 전용 복구 (CL-Worker 겸임 해제)

### 추가된 스크립트
| 스크립트 | 용도 |
|---|---|
| `scripts/fix-dns-gwangyang.ps1` | 광양PC DNS 하이재킹 자동 감지/수정 |
| `scripts/update-discord-hosts.ps1` | Discord 도메인 hosts 자동 업데이트 (주간 작업스케줄러) |

### 추가된 문서
| 문서 | 용도 |
|---|---|
| `docs/dns-hijack-checklist.md` | IT 담당자용 사내DNS 확인 체크리스트 |
| `docs/gwangyang-visit-checklist.md` | 광양PC 방문 시 10분 설정 가이드 |
| `docs/worker-thread-permissions.md` | 워커 봇 스레드 권한 설정 가이드 |

### 런처 재발 방지 로직
`Start-DiscordOrchestrator.ps1`에 추가:
1. 시작 전 좀비 락 자동 정리 (.in_use 디렉터리에서 죽은 PID 락 삭제)
2. 중복 실행 가드 (claude.exe --channels가 실행 중이면 새 인스턴스 시작 안 함)
3. claude.exe 경로 자동 감지 (APPDATA/npm → nvm4w → PATH)

### hosts 자동 업데이트 작업스케줄러
```powershell
# 등록 확인
Get-ScheduledTask -TaskName 'DiscordHostsUpdate'
# 매주 일요일 오전 9시 자동 실행
```

### 워커 봇 스레드 권한 (별도 해결 필요)
워커 봇이 #작업 스레드에 메시지를 게시하려면 Discord 서버 설정에서
각 워커 봇 역할에 "Send Messages in Threads" 권한 부여 필요.
자세한 내용: `docs/worker-thread-permissions.md`

## 아키텍처: channels 플러그인 vs MCP

두 시스템이 하는 일이 다릅니다:

| 구분 | channels 플러그인 | Discord MCP |
|---|---|---|
| 방향 | Discord → PC (메시지 수신) | PC → Discord (명령 전송) |
| 비유 | 자동 전화기 (메시지가 오면 받음) | 리모컨 (원할 때 직접 조작) |
| 용도 | 실시간 대화 응답, 오케스트레이터 | 메시지 조회/전송, 스레드 생성, 연결 확인 |
| 실행 | `claude.exe --channels plugin:discord` | `hermes mcp add discord` 또는 Codex config.toml |
| 주체 | Claude Code CLI | Hermes / Codex / 외부 AI |

### channels 플러그인
- Claude Code CLI가 Discord에서 오는 메시지를 실시간 수신
- 오케스트레이터(지휘자)가 사용자 메시지에 자동 응답
- `~/.claude/channels/discord/.env`의 DISCORD_BOT_TOKEN 사용
- `~/.claude/channels/discord/access.json`으로 접근 제어

### Discord MCP
- Hermes, Codex 등에서 Discord API를 직접 호출
- 4개 도구: 연결 상태 확인, 메시지 조회, 메시지 전송, 스레드 생성
- `D:\program\claude_discord\mcp\discord-mcp.mjs` (Node.js MCP 서버)
- `.env`의 봇 토큰 사용 (ORCH 우선 → CLAUDE fallback)

### Hermes MCP 등록
```bash
hermes mcp add discord --command "node" --args "D:\program\claude_discord\mcp\discord-mcp.mjs"
```
새 세션에서 `discord_connection_status`, `discord_list_messages`, `discord_send_message`, `discord_create_thread` 도구 사용 가능.

### Codex MCP 등록
```toml
[mcp_servers.discord]
enabled = true
command = "node"
args = ['D:\program\claude_discord\mcp\discord-mcp.mjs']
startup_timeout_sec = 30
```

## Hermes 내장 discord toolset vs 커스텀 MCP

Hermes는 두 가지 Discord 연동 방식을 모두 지원합니다:

| 구분 | Hermes 내장 discord toolset | 커스텀 Discord MCP |
|---|---|---|
| 설치 | `hermes tools enable discord` | `hermes mcp add discord` |
| 범용성 | 모든 Hermes 사용자용 | GY 프로젝트 전용 |
| 토큰 관리 | Hermes config/gateway에서 관리 | .env에서 독립 관리 |
| 채널 제한 | Hermes gateway 설정에 따름 | WORK/CHAT 채널만 허용 (allowlist) |
| 역할 분리 | 단일 봇 | 4개 봇(ORCH/CL/Codex/Gm) 역할 분담 |
| 권한 관리 | 없음 | discord_list_roles + discord_update_role_permissions |
| 멘션 제어 | Hermes 설정 | 모든 전송에서 멘션 비활성화 |
| 스레드 생성 | 일반적 | 작업 채널만 제한 |
| 도구 수 | Hermes 버전에 따라 다름 | 6개 (연결/조회/전송/스레드/역할조회/권한수정) |

**GY 프로젝트 추천**: 커스텀 MCP 사용 — 역할 분담(4개 봇), 채널 제한, 권한 관리가 맞춤화되어 있어 Hermes 내장 toolset보다 정확하게 제어 가능.

**일반적 Discord 봇 용도**: Hermes 내장 discord toolset이 간편.
