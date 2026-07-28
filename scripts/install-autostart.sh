#!/usr/bin/env bash
set -euo pipefail

# install-autostart.sh — macOS 로그인 시 오케스트레이터 tmux 세션을 자동 기동한다.
#
# 사용법: install-autostart.sh
#
# - macOS LaunchAgent plist 를 생성하고 등록한다
# - 기존에 등록된 plist 가 있으면 먼저 해제 후 재등록
# - 설정 후 확인 방법을 안내한다

LABEL="com.discord-multiagent.orchestrator"
PLIST_DIR="$HOME/Library/LaunchAgents"
PLIST_PATH="${PLIST_DIR}/${LABEL}.plist"
PROJECT_DIR="$HOME/discord-multiagent"
DISCORD_STATE_DIR="${PROJECT_DIR}/.discord-state"

if [[ "$(uname)" != "Darwin" ]]; then
    echo "[ERROR] 이 스크립트는 macOS 전용입니다." >&2
    exit 1
fi

TMUX_PATH=$(which tmux 2>/dev/null || echo "/opt/homebrew/bin/tmux")
if [ ! -x "$TMUX_PATH" ]; then
    echo "[ERROR] tmux 를 찾을 수 없습니다. brew install tmux 로 설치하세요." >&2
    exit 1
fi

CLAUDE_PATH=$(which claude 2>/dev/null || echo "$HOME/.claude/bin/claude")
if [ ! -x "$CLAUDE_PATH" ]; then
    echo "[WARN] claude 실행 파일을 찾을 수 없습니다: $CLAUDE_PATH" >&2
    echo "       설치 후 이 스크립트를 다시 실행하세요." >&2
fi

mkdir -p "$PLIST_DIR"

if launchctl list "$LABEL" &>/dev/null; then
    echo "기존 LaunchAgent 해제 중..."
    launchctl unload "$PLIST_PATH" 2>/dev/null || true
fi

cat > "$PLIST_PATH" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>${LABEL}</string>
    <key>ProgramArguments</key>
    <array>
        <string>${TMUX_PATH}</string>
        <string>new-session</string>
        <string>-d</string>
        <string>-s</string>
        <string>orchestrator</string>
        <string>-c</string>
        <string>${PROJECT_DIR}</string>
        <string>export DISCORD_STATE_DIR=${DISCORD_STATE_DIR} && ${CLAUDE_PATH} --channels plugin:discord@claude-plugins-official</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>StandardOutPath</key>
    <string>${PROJECT_DIR}/logs/autostart-stdout.log</string>
    <key>StandardErrorPath</key>
    <string>${PROJECT_DIR}/logs/autostart-stderr.log</string>
    <key>WorkingDirectory</key>
    <string>${PROJECT_DIR}</string>
</dict>
</plist>
PLIST

mkdir -p "${PROJECT_DIR}/logs"

launchctl load "$PLIST_PATH"

echo ""
echo "=== 자동 기동 설정 완료 ==="
echo ""
echo "  plist 위치: ${PLIST_PATH}"
echo "  프로젝트:   ${PROJECT_DIR}"
echo "  tmux 세션:  orchestrator"
echo ""
echo "확인 방법:"
echo "  launchctl list | grep ${LABEL}"
echo "  tmux attach -t orchestrator"
echo ""
echo "해제 방법:"
echo "  launchctl unload ${PLIST_PATH}"
echo ""
