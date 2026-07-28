#!/usr/bin/env bash
set -euo pipefail

# post-as.sh — 봇 이름으로 Discord 채널에 메시지를 게시한다.
#
# 사용법: post-as.sh <claude|codex|gemini> <채널ID> <메시지...>
#
# - 역할에 맞는 봇 토큰을 .env 에서 읽어 Discord REST API v10 으로 전송
# - content 는 1900자로 자르고 allowed_mentions 은 {"parse": []} (멘션 방지)
# - JSON 본문은 프로젝트 필수 런타임인 Node.js로 안전하게 만든다
# - DRY_RUN=1 이면 실제 전송 없이 요청 본문만 출력
# - ENV_FILE 환경변수로 다른 .env 파일을 지정할 수 있다

DISCORD_API="https://discord.com/api/v10"

ENV_FILE="${ENV_FILE:-"$(dirname "$(dirname "$0")")/.env"}"

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=load-env.sh
source "${SCRIPT_DIR}/load-env.sh"
load_discord_env "$ENV_FILE"

if [ $# -lt 3 ]; then
    echo "사용법: post-as.sh <claude|codex|gemini> <채널ID> <메시지...>" >&2
    exit 1
fi

ROLE="$1"
CHANNEL_ID="$2"
shift 2
MESSAGE="$*"

case "$ROLE" in
    claude)  TOKEN="${CLAUDE_BOT_TOKEN:-}" ;;
    codex)   TOKEN="${CODEX_BOT_TOKEN:-}" ;;
    gemini)  TOKEN="${GEMINI_BOT_TOKEN:-}" ;;
    *)
        echo "[ERROR] 역할은 claude, codex, gemini 중 하나여야 합니다: $ROLE" >&2
        exit 1
        ;;
esac

if [ -z "$TOKEN" ]; then
    echo "[ERROR] ${ROLE} 봇 토큰이 비어 있습니다. .env 를 확인하세요." >&2
    exit 1
fi

if [ -z "$MESSAGE" ]; then
    echo "[ERROR] 메시지가 비어 있습니다." >&2
    exit 1
fi

if [ -z "$CHANNEL_ID" ]; then
    echo "[ERROR] 채널 ID가 비어 있습니다." >&2
    exit 1
fi

if ! command -v node >/dev/null 2>&1; then
    echo "[ERROR] Node.js를 찾을 수 없습니다." >&2
    exit 1
fi

if [ "${DRY_RUN:-0}" = "1" ]; then
    JSON_BODY=$(node -e \
        'process.stdout.write(JSON.stringify({
            content: Array.from(process.argv[1]).slice(0, 1900).join(""),
            allowed_mentions: {parse: []}
        }))' \
        "$MESSAGE")
    echo "[DRY_RUN] POST ${DISCORD_API}/channels/${CHANNEL_ID}/messages"
    echo "[DRY_RUN] Role: ${ROLE}"
    echo "[DRY_RUN] Body: ${JSON_BODY}"
    exit 0
fi

POST_AS_TOKEN="$TOKEN" node "${SCRIPT_DIR}/discord-post.mjs" "$CHANNEL_ID" "$MESSAGE"
echo "[OK] ${ROLE} → 채널 ${CHANNEL_ID} 게시 완료"
