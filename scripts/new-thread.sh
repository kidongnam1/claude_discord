#!/usr/bin/env bash
set -euo pipefail

# new-thread.sh — 작업 채널에 새 스레드를 만든다.
#
# 사용법: new-thread.sh <스레드 이름>
#
# - .env 의 ORCH_BOT_TOKEN 과 WORK_CHANNEL_ID 로 작업 채널에 스레드 생성
# - 이름은 90자로 자르고, type=11 (공개 스레드), auto_archive_duration=1440 (24시간)
# - 성공 응답 JSON 에서 id 만 뽑아 한 줄 출력
# - DRY_RUN=1 이면 실제 생성 없이 요청 내용만 출력
# - ENV_FILE 환경변수로 다른 .env 파일을 지정할 수 있다

DISCORD_API="https://discord.com/api/v10"

ENV_FILE="${ENV_FILE:-"$(dirname "$(dirname "$0")")/.env"}"

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=load-env.sh
source "${SCRIPT_DIR}/load-env.sh"
load_discord_env "$ENV_FILE"

if [ $# -lt 1 ]; then
    echo "사용법: new-thread.sh <스레드 이름>" >&2
    exit 1
fi

THREAD_NAME="$1"

THREAD_TOKEN="${ORCH_BOT_TOKEN:-${CLAUDE_BOT_TOKEN:-}}"

if [ -z "$THREAD_TOKEN" ]; then
    echo "[ERROR] ORCH_BOT_TOKEN 과 CLAUDE_BOT_TOKEN 이 모두 비어 있습니다. .env 를 확인하세요." >&2
    exit 1
fi

if [ -z "${WORK_CHANNEL_ID:-}" ]; then
    echo "[ERROR] WORK_CHANNEL_ID 가 비어 있습니다. .env 를 확인하세요." >&2
    exit 1
fi

if ! command -v node >/dev/null 2>&1; then
    echo "[ERROR] Node.js를 찾을 수 없습니다." >&2
    exit 1
fi

TRUNCATED_NAME=$(node -e \
    'process.stdout.write(Array.from(process.argv[1]).slice(0, 90).join(""))' \
    "$THREAD_NAME")

JSON_BODY=$(node -e \
    'process.stdout.write(JSON.stringify({
        name: process.argv[1],
        type: 11,
        auto_archive_duration: 1440
    }))' \
    "$TRUNCATED_NAME")

if [ "${DRY_RUN:-0}" = "1" ]; then
    echo "[DRY_RUN] POST ${DISCORD_API}/channels/${WORK_CHANNEL_ID}/threads"
    echo "[DRY_RUN] Body: ${JSON_BODY}"
    exit 0
fi

RESPONSE=$(THREAD_TOKEN="$THREAD_TOKEN" WORK_CHANNEL_ID="$WORK_CHANNEL_ID" JSON_BODY="$JSON_BODY" node -e '
const token = process.env.THREAD_TOKEN;
const channelId = process.env.WORK_CHANNEL_ID;
const body = process.env.JSON_BODY;
fetch(`https://discord.com/api/v10/channels/${channelId}/threads`, {
  method: "POST",
  headers: {
    Authorization: "Bot " + token,
    "Content-Type": "application/json; charset=utf-8",
  },
  body: body,
})
.then(async (resp) => {
  const text = await resp.text();
  process.stdout.write(text);
})
.catch((e) => {
  process.stderr.write(String(e));
  process.exit(1);
});
' 2>&1)

if THREAD_ID=$(node -e '
    const data = JSON.parse(process.argv[1])
    if (!data.id) {
        console.error("[ERROR] " + JSON.stringify(data))
        process.exit(1)
    }
    process.stdout.write(String(data.id))
' "$RESPONSE") && [ -n "$THREAD_ID" ]; then
    echo "$THREAD_ID"

    # ── 워커 봇 3개를 스레드에 자동 추가 ──────────────────────────
    # ORCH 봇이 Administrator 권한이 있어야 워커 봇을 스레드에 추가할 수 있다.
    # 워커 봇이 스레드에 참여해야 메시지를 게시할 수 있다 (Missing Access 50001 방지).
    WORKER_BOT_IDS=("${CLAUDE_BOT_ID:-1531522623597707362}"
                    "${CODEX_BOT_ID:-1531485839035469905}"
                    "${GEMINI_BOT_ID:-1531486384257368280}")

    for WORKER_ID in "${WORKER_BOT_IDS[@]}"; do
        ADD_RESULT=$(THREAD_TOKEN="$THREAD_TOKEN" THREAD_ID="$THREAD_ID" WORKER_ID="$WORKER_ID" node -e '
const token = process.env.THREAD_TOKEN;
const threadId = process.env.THREAD_ID;
const workerId = process.env.WORKER_ID;
fetch(`https://discord.com/api/v10/channels/${threadId}/thread-members/${workerId}`, {
  method: "PUT",
  headers: {
    Authorization: "Bot " + token,
    "Content-Type": "application/json",
  },
  body: JSON.stringify({ user_id: workerId }),
})
.then((resp) => { process.stdout.write(String(resp.status)); })
.catch((e) => { process.stderr.write(String(e)); process.exit(0); });
' 2>&1) || true
        if [ "$ADD_RESULT" = "204" ] || [ "$ADD_RESULT" = "201" ]; then
            echo "[INFO] 워커 봇 ${WORKER_ID} 스레드 참여 완료" >&2
        else
            echo "[WARN] 워커 봇 ${WORKER_ID} 스레드 참여 실패 (HTTP ${ADD_RESULT})" >&2
        fi
    done
else
    echo "[ERROR] 스레드 생성 실패" >&2
    echo "$RESPONSE" >&2
    exit 1
fi
