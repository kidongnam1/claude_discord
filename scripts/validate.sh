#!/usr/bin/env bash
set -euo pipefail

# validate.sh — 로컬과 GitHub Actions에서 동일한 검증을 실행한다.

PROJECT_DIR=$(cd "$(dirname "$0")/.." && pwd)
cd "$PROJECT_DIR"

bash -n scripts/*.sh

test -x scripts/install-autostart.sh
test -x scripts/new-thread.sh
test -x scripts/post-as.sh
test -x scripts/validate.sh

VERSION_VALUE=$(tr -d '\r\n' < VERSION)
if [[ ! "$VERSION_VALUE" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "[ERROR] VERSION은 x.y.z 형식이어야 합니다: $VERSION_VALUE" >&2
    exit 1
fi

if [ "${GITHUB_REF_TYPE:-}" = "tag" ] && [ "${GITHUB_REF_NAME:-}" != "v${VERSION_VALUE}" ]; then
    echo "[ERROR] 태그와 VERSION이 다릅니다: ${GITHUB_REF_NAME:-} != v${VERSION_VALUE}" >&2
    exit 1
fi

grep -qxF '.env' .gitignore
grep -qxF '.env.test' .gitignore
grep -qxF '.discord-state/' .gitignore

TEST_ENV=$(mktemp)
trap 'rm -f "$TEST_ENV"' EXIT

printf '%s\n' \
    'WORK_CHANNEL_ID=123456789012345678' \
    'CHAT_CHANNEL_ID=123456789012345679' \
    'APPROVER_USER_ID=123456789012345680' \
    'ORCH_BOT_TOKEN=dummy-orchestrator-token' \
    'CLAUDE_BOT_TOKEN=dummy-claude-token' \
    'CODEX_BOT_TOKEN=dummy-codex-token' \
    'GEMINI_BOT_TOKEN=dummy-gemini-token' > "$TEST_ENV"

THREAD_OUTPUT=$(DRY_RUN=1 ENV_FILE="$TEST_ENV" ./scripts/new-thread.sh "CI's smoke test")
printf '%s\n' "$THREAD_OUTPUT" | grep -q "\"name\": \"CI's smoke test\""

POST_OUTPUT=$(DRY_RUN=1 ENV_FILE="$TEST_ENV" ./scripts/post-as.sh claude 123456789012345678 "CI smoke test")
printf '%s\n' "$POST_OUTPUT" | grep -q '\[DRY_RUN\] Role: claude'

echo "[OK] 모든 검증을 통과했습니다. VERSION=${VERSION_VALUE}"
