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

TRUNCATED_NAME=$(python3 -c "import sys; print(sys.argv[1][:90])" "$THREAD_NAME" 2>/dev/null || printf '%s\n' "${THREAD_NAME:0:90}")

JSON_BODY=$(python3 -c "
import json, sys
payload = {
    'name': sys.argv[1],
    'type': 11,
    'auto_archive_duration': 1440
}
print(json.dumps(payload, ensure_ascii=False))
" "$TRUNCATED_NAME")

if [ "${DRY_RUN:-0}" = "1" ]; then
    echo "[DRY_RUN] POST ${DISCORD_API}/channels/${WORK_CHANNEL_ID}/threads"
    echo "[DRY_RUN] Body: ${JSON_BODY}"
    exit 0
fi

RESPONSE=$(curl -s \
    -X POST \
    "${DISCORD_API}/channels/${WORK_CHANNEL_ID}/threads" \
    -H "Authorization: Bot ${THREAD_TOKEN}" \
    -H "Content-Type: application/json" \
    -d "$JSON_BODY")

THREAD_ID=$(python3 -c "
import json, sys
data = json.loads(sys.argv[1])
if 'id' in data:
    print(data['id'])
else:
    print('[ERROR] ' + json.dumps(data, ensure_ascii=False), file=sys.stderr)
    sys.exit(1)
" "$RESPONSE")

if [ $? -eq 0 ] && [ -n "$THREAD_ID" ]; then
    echo "$THREAD_ID"
else
    echo "[ERROR] 스레드 생성 실패" >&2
    echo "$RESPONSE" >&2
    exit 1
fi
