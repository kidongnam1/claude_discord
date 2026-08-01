#!/usr/bin/env bash
set -euo pipefail

# harness-status.sh — 하네스 워크플로우 상태 관리
#
# 사용법:
#   harness-status.sh init <thread_id> <작업명>     — 하네스 작업 초기화
#   harness-status.sh stage <thread_id> <stage>     — 현재 단계 설정 (plan/build/review/verify/complete)
#   harness-status.sh approve <thread_id> <gate>    — 승인 (g1/g2/g3/g4)
#   harness-status.sh reject <thread_id> <gate> <이유> — 반려
#   harness-status.sh retry <thread_id>              — 반복 횟수 증가
#   harness-status.sh scale <thread_id> <small|medium|large> — 작업 규모 설정
#   harness-status.sh get <thread_id>                — 현재 상태 조회
#   harness-status.sh list                           — 모든 하네스 작업 목록

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
PROJECT_ROOT=$(cd "$SCRIPT_DIR/.." && pwd)
# MSYS /d/... → D:/... conversion for node compatibility
PROJECT_ROOT_WIN=$(echo "$PROJECT_ROOT" | sed 's|^/\([a-z]\)/|\U\1:/|' | tr '/' '/')
HARNESS_DIR="$PROJECT_ROOT_WIN/.harness-state"
mkdir -p "$HARNESS_DIR"

get_state_file() {
    echo "$HARNESS_DIR/$1.json"
}

init_state() {
    local thread_id="$1"
    local task_name="$2"
    local state_file
    state_file=$(get_state_file "$thread_id")
    cat > "$state_file" << EOF
{
  "thread_id": "$thread_id",
  "task_name": "$task_name",
  "stage": "plan",
  "scale": "medium",
  "retry_count": 0,
  "max_retries": 3,
  "g1_approved": false,
  "g2_score": 0,
  "g3_approved": false,
  "g4_completed": false,
  "created_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "updated_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF
    echo "[INFO] harness init: $task_name (thread=$thread_id)"
}

set_stage() {
    local thread_id="$1"
    local stage="$2"
    local state_file
    state_file=$(get_state_file "$thread_id")
    if [ ! -f "$state_file" ]; then
        echo "[ERROR] harness task not found: $thread_id" >&2
        exit 1
    fi
    node -e "
const fs = require('fs');
const p = process.argv[1];
const s = process.argv[2];
const st = JSON.parse(fs.readFileSync(p, 'utf8'));
st.stage = s;
st.updated_at = new Date().toISOString();
fs.writeFileSync(p, JSON.stringify(st, null, 2));
console.log('[INFO] stage: ' + s);
" "$state_file" "$stage"
}

approve_gate() {
    local thread_id="$1"
    local gate="$2"
    local state_file
    state_file=$(get_state_file "$thread_id")
    if [ ! -f "$state_file" ]; then
        echo "[ERROR] harness task not found: $thread_id" >&2
        exit 1
    fi
    node -e "
const fs = require('fs');
const p = process.argv[1];
const g = process.argv[2];
const st = JSON.parse(fs.readFileSync(p, 'utf8'));
if (g === 'g1') st.g1_approved = true;
if (g === 'g3') st.g3_approved = true;
if (g === 'g4') st.g4_completed = true;
st.updated_at = new Date().toISOString();
fs.writeFileSync(p, JSON.stringify(st, null, 2));
console.log('[INFO] approved: ' + g);
" "$state_file" "$gate"
}

reject_gate() {
    local thread_id="$1"
    local gate="$2"
    local reason="$3"
    local state_file
    state_file=$(get_state_file "$thread_id")
    if [ ! -f "$state_file" ]; then
        echo "[ERROR] harness task not found: $thread_id" >&2
        exit 1
    fi
    node -e "
const fs = require('fs');
const p = process.argv[1];
const g = process.argv[2];
const r = process.argv[3];
const st = JSON.parse(fs.readFileSync(p, 'utf8'));
if (g === 'g2') st.g2_score = 0;
st.updated_at = new Date().toISOString();
fs.writeFileSync(p, JSON.stringify(st, null, 2));
console.log('[INFO] rejected: ' + g + ' — ' + r);
" "$state_file" "$gate" "$reason"
}

increment_retry() {
    local thread_id="$1"
    local state_file
    state_file=$(get_state_file "$thread_id")
    if [ ! -f "$state_file" ]; then
        echo "[ERROR] harness task not found: $thread_id" >&2
        exit 1
    fi
    node -e "
const fs = require('fs');
const p = process.argv[1];
const st = JSON.parse(fs.readFileSync(p, 'utf8'));
st.retry_count++;
st.updated_at = new Date().toISOString();
fs.writeFileSync(p, JSON.stringify(st, null, 2));
console.log('[INFO] retry: ' + st.retry_count + '/' + st.max_retries);
if (st.retry_count >= st.max_retries) {
  console.log('[WARN] max retries reached — user notification needed');
  process.exit(2);
}
" "$state_file"
}

set_scale() {
    local thread_id="$1"
    local scale="$2"
    local state_file
    state_file=$(get_state_file "$thread_id")
    if [ ! -f "$state_file" ]; then
        echo "[ERROR] harness task not found: $thread_id" >&2
        exit 1
    fi
    node -e "
const fs = require('fs');
const p = process.argv[1];
const sc = process.argv[2];
const st = JSON.parse(fs.readFileSync(p, 'utf8'));
st.scale = sc;
st.updated_at = new Date().toISOString();
fs.writeFileSync(p, JSON.stringify(st, null, 2));
console.log('[INFO] scale: ' + sc);
" "$state_file" "$scale"
}

get_state() {
    local thread_id="$1"
    local state_file
    state_file=$(get_state_file "$thread_id")
    if [ ! -f "$state_file" ]; then
        echo "[ERROR] harness task not found: $thread_id" >&2
        exit 1
    fi
    cat "$state_file"
}

list_all() {
    if [ -z "$(ls -A "$HARNESS_DIR" 2>/dev/null)" ]; then
        echo "[INFO] no harness tasks"
        return
    fi
    for f in "$HARNESS_DIR"/*.json; do
        echo "---"
        cat "$f"
        echo ""
    done
}

case "${1:-}" in
    init) init_state "$2" "$3" ;;
    stage) set_stage "$2" "$3" ;;
    approve) approve_gate "$2" "$3" ;;
    reject) reject_gate "$2" "$3" "${4:-no reason}" ;;
    retry) increment_retry "$2" ;;
    scale) set_scale "$2" "$3" ;;
    get) get_state "$2" ;;
    list) list_all ;;
    *) echo "Usage: harness-status.sh <init|stage|approve|reject|retry|scale|get|list> ..." >&2; exit 1 ;;
esac