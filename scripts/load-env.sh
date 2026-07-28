#!/usr/bin/env bash

# .env를 셸 코드로 실행하지 않고 Discord 설정 allowlist만 읽는다.
load_discord_env() {
    local env_file="$1"
    local raw_line key value

    if [ ! -f "$env_file" ]; then
        echo "[ERROR] .env 파일을 찾을 수 없습니다: $env_file" >&2
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
