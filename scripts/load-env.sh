#!/usr/bin/env bash

# .env를 셸 코드로 실행하지 않고 Discord 설정 allowlist만 읽는다.
# 환경변수가 이미 설정되어 있으면 .env 파일 없이도 동작한다.
# (Windows 시스템 환경변수로 설정한 경우 .env 파일 불필요)
load_discord_env() {
    local env_file="$1"
    local raw_line key value

    # 이미 핵심 환경변수가 설정되어 있으면 .env 파일을 읽지 않는다.
    if [[ -n "${WORK_CHANNEL_ID:-}" && -n "${CLAUDE_BOT_TOKEN:-}" && -n "${CODEX_BOT_TOKEN:-}" && -n "${GEMINI_BOT_TOKEN:-}" ]]; then
        return 0
    fi

    if [ ! -f "$env_file" ]; then
        echo "[ERROR] .env 파일을 찾을 수 없고 환경변수도 설정되어 있지 않습니다: $env_file" >&2
        echo "        .env 파일을 생성하거나 시스템 환경변수(WORK_CHANNEL_ID, CLAUDE_BOT_TOKEN, CODEX_BOT_TOKEN, GEMINI_BOT_TOKEN 등)를 설정하세요." >&2
        return 1
    fi

    while IFS= read -r raw_line || [ -n "$raw_line" ]; do
        raw_line="${raw_line%$'\r'}"
        case "$raw_line" in
            ""|\#*) continue ;;
        esac

        key="${raw_line%%=*}"
        if [ "$key" = "$raw_line" ]; then
            continue
        fi
        value="${raw_line#*=}"

        case "$key" in
            WORK_CHANNEL_ID|CHAT_CHANNEL_ID|APPROVER_USER_ID|ORCH_BOT_TOKEN|CLAUDE_BOT_TOKEN|CODEX_BOT_TOKEN|GEMINI_BOT_TOKEN)
                # 이미 환경변수로 설정된 값이 있으면 덮어쓰지 않는다 (환경변수 우선)
                if [ -n "${!key:-}" ]; then
                    continue
                fi
                value="${value#"${value%%[![:space:]]*}"}"
                value="${value%"${value##*[![:space:]]}"}"
                if [[ "$value" == \"*\" && "$value" == *\" ]]; then
                    value="${value:1:${#value}-2}"
                elif [[ "$value" == \'*\' && "$value" == *\' ]]; then
                    value="${value:1:${#value}-2}"
                fi
                printf -v "$key" '%s' "$value"
                ;;
        esac
    done < "$env_file"
}
