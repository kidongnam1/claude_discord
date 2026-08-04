#!/usr/bin/env bash
set -euo pipefail

# validate.sh — 로컬과 GitHub Actions에서 동일한 검증을 실행한다.

PROJECT_DIR=$(cd "$(dirname "$0")/.." && pwd)
cd "$PROJECT_DIR"

bash -n scripts/*.sh

test -x scripts/install-autostart.sh
test -x scripts/load-env.sh
test -x scripts/new-thread.sh
test -x scripts/post-as.sh
test -x scripts/validate.sh
test -f scripts/Test-DiscordConnection.ps1
test -f mcp/discord-mcp.mjs
test -f router/discord-ai-router.mjs
test -f router/router-core.mjs
test -f router/job-store.mjs
test -f scripts/Start-DiscordAiRouter.ps1
test -f scripts/install-router-autostart.ps1
test -f scripts/setup-router.ps1

VERSION_VALUE=$(tr -d '\r\n' < VERSION)
if [[ ! "$VERSION_VALUE" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "[ERROR] VERSION은 x.y.z 형식이어야 합니다: $VERSION_VALUE" >&2
    exit 1
fi

if [ "${GITHUB_REF_TYPE:-}" = "tag" ] && [ "${GITHUB_REF_NAME:-}" != "v${VERSION_VALUE}" ]; then
    echo "[ERROR] 태그와 VERSION이 다릅니다: ${GITHUB_REF_NAME:-} != v${VERSION_VALUE}" >&2
    exit 1
fi

grep -qxF '.env' <(tr -d '\r' < .gitignore)
grep -qxF '.env.test' <(tr -d '\r' < .gitignore)
grep -qxF '.discord-state/' <(tr -d '\r' < .gitignore)
grep -qxF '.discord-router/' <(tr -d '\r' < .gitignore)

if grep -Eq '^[A-Z_]+=[[:space:]]+[^#[:space:]]' .env.example; then
    echo "[ERROR] .env.example 값 앞에 공백이 있습니다." >&2
    exit 1
fi

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
printf '%s\n' "$THREAD_OUTPUT" | grep -q '"name":"CI'"'"'s smoke test"'

POST_OUTPUT=$(DRY_RUN=1 ENV_FILE="$TEST_ENV" ./scripts/post-as.sh claude 123456789012345678 "CI smoke test")
printf '%s\n' "$POST_OUTPUT" | grep -q '\[DRY_RUN\] Role: claude'

MALICIOUS_MARKER=$(mktemp)
rm -f "$MALICIOUS_MARKER"
printf '%s\n' \
    'WORK_CHANNEL_ID=123456789012345678' \
    'CLAUDE_BOT_TOKEN=$(touch should-not-run)' \
    "UNSUPPORTED=\$(touch \"$MALICIOUS_MARKER\")" > "$TEST_ENV"
DRY_RUN=1 ENV_FILE="$TEST_ENV" ./scripts/post-as.sh claude 123456789012345678 "safe env parse" >/dev/null
if [ -e "$MALICIOUS_MARKER" ] || [ -e "should-not-run" ]; then
    echo "[ERROR] .env 값이 셸 코드로 실행됐습니다." >&2
    exit 1
fi

npm test

echo "[OK] 모든 검증을 통과했습니다. VERSION=${VERSION_VALUE}"
