# -*- coding: utf-8 -*-
"""
Discord Multi-Agent Orchestrator Web Server
=============================================
표준 라이브러리만 사용한 웹 서버 기반 오케스트레이터 관리 콘솔.
PyWebView 버전(orchestrator_gui.py)과 동일한 기능을 제공하지만
HTTP 서버로 동작하여 Tailscale 을 통해 휴대폰에서 접속 가능.

기능:
  - 오케스트레이터 시작 / 재시작
  - 연결 테스트 / DNS 체크
  - 일일 리포트 즉시 생성
  - 하네스 상태 목록
  - 상태 표시 (claude.exe 실행 여부, .in_use 락 개수, Discord 연결)
  - Discord 명령 입력 (#수다 / #작업 채널로 전송)
  - 스레드 생성
  - 10초마다 상태 자동 새로고침

외부 의존성: 없음 (Python 표준 라이브러리만 사용)
실행: python orchestrator_web.py
접속: http://100.87.8.86:8870  (Tailscale) 또는 http://localhost:8870

작성자: Hermes Agent
"""

import os
import sys
import json
import subprocess
import threading
import time
import socket
import urllib.request
import urllib.error
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse

# =============================================================================
# 경로 상수
# =============================================================================
BASE_DIR = r"D:\program\claude_discord"
ENV_PATH = os.path.join(BASE_DIR, ".env")
SCRIPTS_DIR = os.path.join(BASE_DIR, "scripts")

START_PS1 = os.path.join(SCRIPTS_DIR, "Start-DiscordOrchestratorVisible.ps1")
TEST_CONN_PS1 = os.path.join(SCRIPTS_DIR, "Test-DiscordConnection.ps1")
DAILY_REPORT_JS = os.path.join(SCRIPTS_DIR, "discord-daily-report.mjs")
HARNESS_STATUS_SH = os.path.join(SCRIPTS_DIR, "harness-status.sh")
NEW_THREAD_SH = os.path.join(SCRIPTS_DIR, "new-thread.sh")

# .in_use 락 파일 디렉토리
IN_USE_DIR = os.path.join(
    os.path.expanduser("~"),
    ".claude",
    "plugins",
    "cache",
    "claude-plugins-official",
    "discord",
    "0.0.4",
    ".in_use",
)

# Discord gateway (TCP 연결 테스트용)
DISCORD_HOST = "gateway.discord.gg"
DISCORD_PORT = 443

# 웹 서버 설정
HOST = "0.0.0.0"
PORT = 8870
TAILSCALE_URL = "http://100.87.8.86:8870"

# =============================================================================
# .env 파일 로드 (토큰은 절대 출력하지 않음)
# =============================================================================

def load_env(path=ENV_PATH):
    """간단한 .env 파서. KEY=VALUE 형식을 읽어 딕셔너리로 반환."""
    env = {}
    if not os.path.exists(path):
        return env
    try:
        with open(path, "r", encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if not line or line.startswith("#"):
                    continue
                if "=" not in line:
                    continue
                key, _, value = line.partition("=")
                key = key.strip()
                value = value.strip().strip('"').strip("'")
                if key:
                    env[key] = value
    except Exception as e:
        print(f"[env 로드 오류] {e}", file=sys.stderr)
    return env


# 환경 변수는 서버 시작 시 한 번 로드
ENV = load_env()
IS_WINDOWS = (os.name == "nt")

# =============================================================================
# 상태 확인 함수들
# =============================================================================

def check_claude_running():
    """claude.exe 프로세스가 실행 중인지 확인 (tasklist 사용)."""
    try:
        result = subprocess.run(
            ["tasklist"],
            capture_output=True,
            text=True,
            timeout=10,
            encoding="utf-8",
            errors="replace",
        )
        if result.returncode == 0:
            for raw in result.stdout.splitlines():
                parts = raw.split()
                if parts and parts[0].lower() == "claude.exe":
                    return True, "실행 중"
        return False, "미실행"
    except FileNotFoundError:
        # Windows 가 아닌 환경 (테스트용) — ps 기반 시도
        try:
            result = subprocess.run(
                ["ps", "-A"],
                capture_output=True,
                text=True,
                timeout=10,
            )
            running = any("claude" in line.lower() for line in result.stdout.splitlines())
            return (running, "실행 중" if running else "미실행")
        except Exception:
            return (False, "확인 불가")
    except Exception as e:
        return (False, f"오류: {e}")


def count_in_use_locks():
    """.in_use 디렉토리 내 파일 개수 반환."""
    if not os.path.isdir(IN_USE_DIR):
        return 0, "디렉토리 없음"
    try:
        files = os.listdir(IN_USE_DIR)
        count = len([f for f in files if os.path.isfile(os.path.join(IN_USE_DIR, f))])
        return count, f"{count}개 락"
    except Exception as e:
        return -1, f"오류: {e}"


def check_discord_connection():
    """gateway.discord.gg:443 TCP 연결 테스트."""
    try:
        try:
            ip = socket.gethostbyname(DISCORD_HOST)
        except socket.gaierror:
            return (False, "DNS 해석 실패")

        sock = socket.create_connection((ip, DISCORD_PORT), timeout=5)
        sock.close()
        return (True, f"연결됨 ({ip})")
    except Exception as e:
        return (False, f"연결 실패: {e}")


def get_status():
    """전체 상태를 dict로 반환."""
    claude_running, claude_msg = check_claude_running()
    lock_count, lock_msg = count_in_use_locks()
    discord_ok, discord_msg = check_discord_connection()

    return {
        "claude_running": claude_running,
        "claude_msg": claude_msg,
        "lock_count": lock_count,
        "lock_msg": lock_msg,
        "discord_ok": discord_ok,
        "discord_msg": discord_msg,
        "timestamp": time.strftime("%Y-%m-%d %H:%M:%S"),
    }


# =============================================================================
# API 액션 함수들 (HTTP 핸들러에서 호출)
# =============================================================================

def api_start_orchestrator():
    """PowerShell 스크립트로 오케스트레이터 시작."""
    try:
        cmd = [
            "powershell",
            "-NoProfile",
            "-ExecutionPolicy", "Bypass",
            "-File", START_PS1,
        ]
        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=60,
            encoding="utf-8",
            errors="replace",
        )
        return {
            "ok": result.returncode == 0,
            "stdout": result.stdout or "",
            "stderr": result.stderr or "",
            "code": result.returncode,
        }
    except Exception as e:
        return {"ok": False, "stdout": "", "stderr": str(e), "code": -1}


def api_restart_orchestrator():
    """claude.exe 종료 후 다시 시작."""
    try:
        # 1) taskkill
        kill = subprocess.run(
            ["taskkill", "/IM", "claude.exe", "/F"],
            capture_output=True,
            text=True,
            timeout=15,
            encoding="utf-8",
            errors="replace",
        )
        kill_msg = (kill.stdout or "") + (kill.stderr or "")

        # 2) 잠시 대기
        time.sleep(2)

        # 3) 시작
        start = api_start_orchestrator()
        return {
            "ok": start["ok"],
            "stdout": f"[taskkill]\n{kill_msg}\n\n[start]\n{start['stdout']}",
            "stderr": start["stderr"],
            "code": start["code"],
        }
    except Exception as e:
        return {"ok": False, "stdout": "", "stderr": str(e), "code": -1}


def api_test_connection():
    """
    Python 에서 직접 Discord API 호출로 연결 테스트.
    PowerShell 한글 깨짐 방지를 위해 urllib.request 사용.
    3개 봇(CL-Worker, codex-worker, Gm-Worker)의 #수다/#작업 채널 접근 확인.
    """
    try:
        results = []
        all_ok = True

        roles = [
            ("claude", "CLAUDE_BOT_TOKEN", "CL-Worker"),
            ("codex", "CODEX_BOT_TOKEN", "codex-worker"),
            ("gemini", "GEMINI_BOT_TOKEN", "Gm-Worker"),
        ]

        chat_id = ENV.get("CHAT_CHANNEL_ID", "")
        work_id = ENV.get("WORK_CHANNEL_ID", "")

        for role, token_key, bot_name in roles:
            token = ENV.get(token_key, "")
            if not token:
                results.append(f"{bot_name}: TOKEN_MISSING")
                all_ok = False
                continue
            try:
                # 봇 정보 확인
                req = urllib.request.Request(
                    "https://discord.com/api/v10/users/@me",
                    headers={
                        "Authorization": f"Bot {token}",
                        "User-Agent": "OrchestratorWeb/1.0",
                    },
                )
                with urllib.request.urlopen(req, timeout=10) as resp:
                    bot_data = json.loads(resp.read().decode("utf-8"))

                # 채널 접근 확인 — #수다와 #작업 모두
                ch_names = []
                for ch_id in [chat_id, work_id]:
                    if ch_id:
                        try:
                            req2 = urllib.request.Request(
                                f"https://discord.com/api/v10/channels/{ch_id}",
                                headers={
                                    "Authorization": f"Bot {token}",
                                    "User-Agent": "OrchestratorWeb/1.0",
                                },
                            )
                            with urllib.request.urlopen(req2, timeout=10) as resp2:
                                ch_data = json.loads(resp2.read().decode("utf-8"))
                            ch_names.append(f"#{ch_data.get('name', '?')}")
                        except Exception:
                            ch_names.append("#(접근불가)")
                ch_str = ", ".join(ch_names) if ch_names else "(no channel)"
                results.append(f"{bot_name:15s}  {ch_str:20s}  CONNECTED")
            except urllib.error.HTTPError as e:
                results.append(f"{bot_name:15s}  FAILED (HTTP {e.code})")
                all_ok = False
            except Exception as e:
                results.append(f"{bot_name:15s}  FAILED ({e})")
                all_ok = False

        output = f"{'Role':<15s}  {'Channels':<22s}  {'Status'}\n"
        output += f"{'─'*15}  {'─'*22}  {'─'*10}\n"
        output += "\n".join(results)

        return {
            "ok": all_ok,
            "stdout": output,
            "stderr": "",
            "code": 0 if all_ok else 1,
        }
    except Exception as e:
        return {"ok": False, "stdout": "", "stderr": str(e), "code": -1}


def api_dns_check():
    """nslookup gateway.discord.gg 실행."""
    try:
        cmd = ["nslookup", DISCORD_HOST]
        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=15,
            encoding="utf-8",
            errors="replace",
        )
        return {
            "ok": result.returncode == 0,
            "stdout": result.stdout or "",
            "stderr": result.stderr or "",
            "code": result.returncode,
        }
    except Exception as e:
        return {"ok": False, "stdout": "", "stderr": str(e), "code": -1}


def api_daily_report():
    """node scripts/discord-daily-report.mjs 실행."""
    try:
        cmd = ["node", DAILY_REPORT_JS]
        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=120,
            encoding="utf-8",
            errors="replace",
            cwd=BASE_DIR,
        )
        return {
            "ok": result.returncode == 0,
            "stdout": result.stdout or "",
            "stderr": result.stderr or "",
            "code": result.returncode,
        }
    except Exception as e:
        return {"ok": False, "stdout": "", "stderr": str(e), "code": -1}


def api_harness_status():
    """./scripts/harness-status.sh list 실행 후 JSON 구조화하여 반환."""
    try:
        cmd = ["bash", "scripts/harness-status.sh", "list"]
        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=30,
            encoding="utf-8",
            errors="replace",
            cwd=BASE_DIR,
        )
        stdout = result.stdout or ""
        tasks = []
        blocks = stdout.split("---")
        for block in blocks:
            block = block.strip()
            if not block:
                continue
            try:
                task = json.loads(block)
                tasks.append(task)
            except json.JSONDecodeError:
                continue
        return {
            "ok": result.returncode == 0,
            "tasks": tasks,
            "count": len(tasks),
            "raw": stdout,
            "stderr": result.stderr or "",
            "code": result.returncode,
        }
    except Exception as e:
        return {"ok": False, "tasks": [], "count": 0, "raw": "", "stderr": str(e), "code": -1}


def api_send_discord_message(channel_type, message):
    """
    Discord API 로 메시지 전송.
    channel_type: 'chat' (#수다) 또는 'work' (#작업)
    """
    try:
        # 채널 ID / 토큰 선택
        if channel_type == "chat":
            channel_id = ENV.get("CHAT_CHANNEL_ID", "")
        elif channel_type == "work":
            channel_id = ENV.get("WORK_CHANNEL_ID", "")
        else:
            return {"ok": False, "error": "알 수 없는 채널 타입"}

        token = ENV.get("ORCH_BOT_TOKEN", "")

        if not channel_id:
            return {"ok": False, "error": f"채널 ID 가 없습니다 ({channel_type})"}
        if not token:
            return {"ok": False, "error": "ORCH_BOT_TOKEN 이 없습니다"}
        if not message or not message.strip():
            return {"ok": False, "error": "메시지가 비어 있습니다"}

        url = f"https://discord.com/api/v10/channels/{channel_id}/messages"
        payload = json.dumps({
            "content": message,
            "allowed_mentions": {"parse": []},
        }).encode("utf-8")

        req = urllib.request.Request(
            url,
            data=payload,
            headers={
                "Authorization": f"Bot {token}",
                "Content-Type": "application/json",
                "User-Agent": "OrchestratorWeb/1.0",
            },
            method="POST",
        )

        try:
            with urllib.request.urlopen(req, timeout=15) as resp:
                body = resp.read().decode("utf-8", errors="replace")
                return {"ok": True, "status": resp.status, "response": body}
        except urllib.error.HTTPError as e:
            body = e.read().decode("utf-8", errors="replace")
            return {"ok": False, "error": f"HTTP {e.code}", "response": body}
        except urllib.error.URLError as e:
            return {"ok": False, "error": str(e.reason)}

    except Exception as e:
        return {"ok": False, "error": str(e)}


def api_create_thread(thread_name):
    """scripts/new-thread.sh 실행 후 thread_id 반환 (상대경로 — cwd=BASE_DIR)."""
    try:
        if not thread_name or not thread_name.strip():
            return {"ok": False, "error": "스레드 이름이 비어 있습니다", "stdout": ""}

        # git-bash 경로 호환을 위해 상대경로 사용
        cmd = ["bash", "scripts/new-thread.sh", thread_name.strip()]
        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=30,
            encoding="utf-8",
            errors="replace",
            cwd=BASE_DIR,
        )
        return {
            "ok": result.returncode == 0,
            "stdout": result.stdout or "",
            "stderr": result.stderr or "",
            "code": result.returncode,
        }
    except Exception as e:
        return {"ok": False, "stdout": "", "stderr": str(e), "code": -1}


# =============================================================================
# HTML / CSS / JS (임베디드 — fetch() 기반, PyWebView 의존성 제거)
# =============================================================================

HTML_CONTENT = r"""<!DOCTYPE html>
<html lang="ko">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Discord Orchestrator</title>
<style>
:root {
    --bg: #1a1a2e;
    --bg-card: #16213e;
    --bg-card-hover: #1a2744;
    --accent: #c9a84c;
    --accent-dim: #8a7236;
    --accent-glow: rgba(201, 168, 76, 0.3);
    --text: #e0e0e0;
    --text-dim: #8a8a9a;
    --green: #4ecca3;
    --red: #e74c5e;
    --border: #2a2a4a;
    --radius: 12px;
}

* {
    box-sizing: border-box;
    margin: 0;
    padding: 0;
}

body {
    background: var(--bg);
    color: var(--text);
    font-family: "Segoe UI", "Malgun Gothic", "Apple SD Gothic Neo", sans-serif;
    padding: 18px;
    font-size: 14px;
    line-height: 1.5;
}

h1 {
    text-align: center;
    color: var(--accent);
    font-size: 22px;
    font-weight: 600;
    margin-bottom: 4px;
    letter-spacing: 1px;
}

.subtitle {
    text-align: center;
    color: var(--text-dim);
    font-size: 12px;
    margin-bottom: 18px;
}

.card {
    background: var(--bg-card);
    border: 1px solid var(--border);
    border-radius: var(--radius);
    padding: 16px;
    margin-bottom: 14px;
    transition: border-color 0.2s;
}

.card:hover {
    border-color: var(--accent-dim);
}

.card-title {
    font-size: 13px;
    color: var(--accent);
    font-weight: 600;
    margin-bottom: 12px;
    text-transform: uppercase;
    letter-spacing: 1.2px;
    display: flex;
    align-items: center;
    gap: 6px;
}

.btn {
    background: var(--bg-card-hover);
    color: var(--text);
    border: 1px solid var(--border);
    border-radius: 8px;
    padding: 10px 14px;
    font-size: 13px;
    font-weight: 600;
    cursor: pointer;
    transition: all 0.15s;
    font-family: inherit;
    display: inline-flex;
    align-items: center;
    gap: 6px;
    white-space: nowrap;
}

.btn:hover {
    background: var(--accent);
    color: #1a1a2e;
    border-color: var(--accent);
    box-shadow: 0 0 12px var(--accent-glow);
}

.btn:active {
    transform: scale(0.97);
}

.btn:disabled {
    opacity: 0.5;
    cursor: not-allowed;
}

.btn-primary {
    border-color: var(--accent-dim);
}

.btn-row {
    display: flex;
    flex-wrap: wrap;
    gap: 8px;
}

.status-grid {
    display: grid;
    grid-template-columns: 1fr;
    gap: 10px;
}

.status-item {
    display: flex;
    justify-content: space-between;
    align-items: center;
    padding: 10px 12px;
    background: rgba(0,0,0,0.2);
    border-radius: 8px;
    border-left: 3px solid var(--border);
}

.status-item.ok {
    border-left-color: var(--green);
}

.status-item.bad {
    border-left-color: var(--red);
}

.status-label {
    color: var(--text-dim);
    font-size: 12px;
}

.status-value {
    font-weight: 600;
    font-size: 13px;
    display: flex;
    align-items: center;
    gap: 5px;
}

.dot {
    width: 8px;
    height: 8px;
    border-radius: 50%;
    display: inline-block;
}

.dot.ok { background: var(--green); box-shadow: 0 0 6px var(--green); }
.dot.bad { background: var(--red); box-shadow: 0 0 6px var(--red); }
.dot.warn { background: var(--accent); box-shadow: 0 0 6px var(--accent); }

.input {
    width: 100%;
    background: rgba(0,0,0,0.25);
    border: 1px solid var(--border);
    border-radius: 8px;
    padding: 10px 12px;
    color: var(--text);
    font-size: 13px;
    font-family: inherit;
    outline: none;
    transition: border-color 0.2s;
}

.input:focus {
    border-color: var(--accent);
}

.input::placeholder {
    color: var(--text-dim);
}

textarea.input {
    resize: vertical;
    min-height: 60px;
    font-family: "Consolas", "Malgun Gothic", monospace;
}

.output-box {
    background: #0d0d1a;
    border: 1px solid var(--border);
    border-radius: 8px;
    padding: 10px 12px;
    font-family: "Consolas", monospace;
    font-size: 12px;
    color: #a0d0a0;
    max-height: 200px;
    overflow-y: auto;
    white-space: pre-wrap;
    word-break: break-all;
    margin-top: 10px;
    display: none;
}

.output-box.show {
    display: block;
}

.output-box.error {
    color: var(--red);
}

.timestamp {
    text-align: right;
    color: var(--text-dim);
    font-size: 10px;
    margin-top: 6px;
}

.divider {
    height: 1px;
    background: var(--border);
    margin: 12px 0;
}

.label {
    font-size: 11px;
    color: var(--text-dim);
    margin-bottom: 5px;
    text-transform: uppercase;
    letter-spacing: 0.8px;
}

.channel-group {
    display: flex;
    gap: 8px;
    margin-top: 8px;
}

.channel-group .btn {
    flex: 1;
    justify-content: center;
}

.thread-row {
    display: flex;
    gap: 8px;
}

.thread-row .input {
    flex: 1;
}

.thread-id-display {
    margin-top: 8px;
    padding: 8px 12px;
    background: rgba(201, 168, 76, 0.1);
    border: 1px solid var(--accent-dim);
    border-radius: 8px;
    font-family: "Consolas", monospace;
    font-size: 13px;
    color: var(--accent);
    display: none;
}

.thread-id-display.show {
    display: block;
}

/* 스크롤바 */
::-webkit-scrollbar { width: 6px; }
::-webkit-scrollbar-track { background: #0d0d1a; }
::-webkit-scrollbar-thumb { background: var(--accent-dim); border-radius: 3px; }

/* 로딩 스피너 */
.spinner {
    display: inline-block;
    width: 12px;
    height: 12px;
    border: 2px solid var(--border);
    border-top-color: var(--accent);
    border-radius: 50%;
    animation: spin 0.6s linear infinite;
}
@keyframes spin { to { transform: rotate(360deg); } }
</style>
</head>
<body>

<h1>🎮 Discord Orchestrator</h1>
<div class="subtitle">멀티 에이전트 오케스트레이터 관리 콘솔</div>

<!-- ===== 상태 카드 ===== -->
<div class="card">
    <div class="card-title">📊 시스템 상태</div>
    <div class="status-grid" id="statusGrid">
        <div class="status-item" id="statusClaude">
            <span class="status-label">claude.exe 프로세스</span>
            <span class="status-value"><span class="dot warn"></span><span id="claudeMsg">확인 중...</span></span>
        </div>
        <div class="status-item" id="statusLock">
            <span class="status-label">.in_use 락 파일</span>
            <span class="status-value"><span class="dot warn"></span><span id="lockMsg">확인 중...</span></span>
        </div>
        <div class="status-item" id="statusDiscord">
            <span class="status-label">Discord TCP 연결</span>
            <span class="status-value"><span class="dot warn"></span><span id="discordMsg">확인 중...</span></span>
        </div>
    </div>
    <div class="timestamp" id="statusTime">-</div>
</div>

<!-- ===== 오케스트레이터 제어 ===== -->
<div class="card">
    <div class="card-title">⚙️ 오케스트레이터 제어</div>
    <div class="btn-row">
        <button class="btn btn-primary" onclick="runCmd('/api/start', this)">▶️ 시작</button>
        <button class="btn btn-primary" onclick="runCmd('/api/restart', this)">🔄 재시작</button>
        <button class="btn" onclick="runCmd('/api/test_connection', this)">🔌 연결 테스트</button>
        <button class="btn" onclick="runCmd('/api/dns_check', this)">🌐 DNS 체크</button>
    </div>
    <div class="output-box" id="outOrch"></div>
</div>

<!-- ===== 리포트 & 하네스 ===== -->
<div class="card">
    <div class="card-title">📈 리포트 & 하네스</div>
    <div class="btn-row">
        <button class="btn" onclick="runCmd('/api/daily_report', this)">📋 일일 리포트</button>
        <button class="btn" onclick="runCmd('/api/harness_status', this)">🧩 하네스 상태</button>
    </div>
    <div class="output-box" id="outReport"></div>
</div>

<!-- ===== Discord 메시지 전송 ===== -->
<div class="card">
    <div class="card-title">💬 Discord 명령 전송</div>
    <div class="label">명령 / 메시지 입력</div>
    <textarea class="input" id="msgInput" placeholder="전송할 메시지를 입력하세요..."></textarea>
    <div class="channel-group">
        <button class="btn btn-primary" onclick="sendMsg('chat', this)">📤 #수다 로 전송</button>
        <button class="btn btn-primary" onclick="sendMsg('work', this)">📤 #작업 로 전송</button>
    </div>
    <div class="output-box" id="outMsg"></div>
</div>

<!-- ===== 스레드 생성 ===== -->
<div class="card">
    <div class="card-title">🧵 스레드 생성</div>
    <div class="label">스레드 이름</div>
    <div class="thread-row">
        <input class="input" id="threadName" type="text" placeholder="새 스레드 이름 입력..." />
        <button class="btn btn-primary" onclick="createThread(this)">➕ 생성</button>
    </div>
    <div class="thread-id-display" id="threadIdDisplay"></div>
    <div class="output-box" id="outThread"></div>
</div>

<script>
// =========================================================================
// HTTP API 호출 헬퍼 (fetch 기반 — PyWebView 의존성 제거)
// =========================================================================

// HTML 이스케이프 (XSS 방지)
function escapeHtml(s) {
    return String(s).replace(/[&<>"']/g, c => ({
        '&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'
    }[c]));
}

// GET 요청 (JSON 응답)
async function apiGet(url) {
    const resp = await fetch(url, { method: 'GET' });
    if (!resp.ok) throw new Error('HTTP ' + resp.status);
    return resp.json();
}

// POST 요청 (JSON 응답, 본문 선택)
async function apiPost(url, body) {
    const opts = { method: 'POST' };
    if (body !== undefined) {
        opts.headers = { 'Content-Type': 'application/json' };
        opts.body = JSON.stringify(body);
    }
    const resp = await fetch(url, opts);
    if (!resp.ok) throw new Error('HTTP ' + resp.status);
    return resp.json();
}

// ------------------------------------------------------------------
// 상태 새로고침
// ------------------------------------------------------------------
async function updateStatus() {
    try {
        const s = await apiGet('/api/status');
        if (!s) return;

        // claude.exe
        let elClaude = document.getElementById('statusClaude');
        let dotClaude = elClaude.querySelector('.dot');
        dotClaude.className = 'dot ' + (s.claude_running ? 'ok' : 'bad');
        elClaude.className = 'status-item ' + (s.claude_running ? 'ok' : 'bad');
        document.getElementById('claudeMsg').textContent = s.claude_msg;

        // lock
        let elLock = document.getElementById('statusLock');
        let dotLock = elLock.querySelector('.dot');
        let lockGood = s.lock_count >= 0 && s.lock_count === 0;
        let lockBad = s.lock_count > 0;
        dotLock.className = 'dot ' + (lockGood ? 'ok' : (lockBad ? 'bad' : 'warn'));
        elLock.className = 'status-item ' + (lockGood ? 'ok' : (lockBad ? 'bad' : ''));
        document.getElementById('lockMsg').textContent = s.lock_msg;

        // discord
        let elDisc = document.getElementById('statusDiscord');
        let dotDisc = elDisc.querySelector('.dot');
        dotDisc.className = 'dot ' + (s.discord_ok ? 'ok' : 'bad');
        elDisc.className = 'status-item ' + (s.discord_ok ? 'ok' : 'bad');
        document.getElementById('discordMsg').textContent = s.discord_msg;

        document.getElementById('statusTime').textContent = '업데이트: ' + s.timestamp;
    } catch (e) {
        // 서버 일시적 오류 — 다음 폴링에서 재시도
        console.warn('상태 새로고침 실패:', e);
    }
}

// ------------------------------------------------------------------
// 일반 명령 실행 (시작/재시작/연결/DNS/리포트/하네스)
// ------------------------------------------------------------------
async function runCmd(url, btn) {
    let outputId = url.includes('daily_report') || url.includes('harness_status')
        ? 'outReport' : 'outOrch';
    let out = document.getElementById(outputId);
    let origText = btn.innerHTML;
    btn.disabled = true;
    btn.innerHTML = '<span class="spinner"></span> 실행 중...';

    try {
        const r = await apiPost(url);
        out.classList.add('show');
        out.classList.remove('error');
        let txt = '';
        if (url.includes('harness_status') && r.tasks) {
            txt = renderHarnessDashboard(r);
        } else {
            if (r.stdout) txt += r.stdout;
            if (r.raw) txt += r.raw;
            if (r.stderr) txt += (txt ? '\n' : '') + r.stderr;
            if (!txt) txt = (r.ok ? '✅ 완료' : '❌ 실패') + ' (exit ' + r.code + ')';
            else txt += '\n--- [exit ' + r.code + '] ' + (r.ok ? '성공' : '실패') + ' ---';
        }
        out.textContent = txt;
    } catch (e) {
        out.classList.add('show', 'error');
        out.textContent = '오류: ' + escapeHtml(e.message || e);
    } finally {
        btn.disabled = false;
        btn.innerHTML = origText;
        updateStatus();
    }
}

function renderHarnessDashboard(r) {
    if (!r.tasks || r.tasks.length === 0) {
        return '🧩 하네스 작업 없음 (0개)';
    }
    const stageEmoji = { plan: '📋', build: '🔨', review: '🔍', verify: '✅', complete: '🏁' };
    const scaleEmoji = { small: 'S', medium: 'M', large: 'L' };
    let lines = ['🧩 하네스 작업 ' + r.count + '개', ''];
    for (const t of r.tasks) {
        let stage = t.stage || '?';
        let emoji = stageEmoji[stage] || '❓';
        let scale = scaleEmoji[t.scale] || '?';
        let g1 = t.g1_approved ? '✅' : '⬜';
        let g4 = t.g4_completed ? '✅' : '⬜';
        let retry = t.retry_count || 0;
        let retryWarn = retry >= (t.max_retries || 3) ? ' ⚠️MAX' : (retry > 0 ? ' ↻' + retry : '');
        lines.push(emoji + ' [' + scale + '] ' + (t.task_name || t.thread_id || '?'));
        lines.push('   단계: ' + stage + ' | G1:' + g1 + ' G4:' + g4 + retryWarn);
        lines.push('   thread: ' + (t.thread_id || '?'));
        lines.push('');
    }
    lines.push('--- [exit ' + r.code + '] ' + (r.ok ? '성공' : '실패') + ' ---');
    return lines.join('\n');
}

// ------------------------------------------------------------------
// Discord 메시지 전송
// ------------------------------------------------------------------
async function sendMsg(channelType, btn) {
    let input = document.getElementById('msgInput');
    let msg = input.value.trim();
    let out = document.getElementById('outMsg');
    let origText = btn.innerHTML;

    if (!msg) {
        out.classList.add('show', 'error');
        out.textContent = '⚠️ 메시지를 입력하세요.';
        return;
    }

    btn.disabled = true;
    btn.innerHTML = '<span class="spinner"></span> 전송 중...';

    try {
        const r = await apiPost('/api/send_message', { channel: channelType, message: msg });
        out.classList.add('show');
        out.classList.remove('error');
        if (r.ok) {
            out.textContent = '✅ 전송 성공 (HTTP ' + r.status + ')\n' + (r.response || '');
            input.value = '';
        } else {
            out.classList.add('error');
            out.textContent = '❌ 전송 실패: ' + escapeHtml(r.error || r.response || '알 수 없음');
        }
    } catch (e) {
        out.classList.add('show', 'error');
        out.textContent = '오류: ' + escapeHtml(e.message || e);
    } finally {
        btn.disabled = false;
        btn.innerHTML = origText;
    }
}

// ------------------------------------------------------------------
// 스레드 생성
// ------------------------------------------------------------------
async function createThread(btn) {
    let input = document.getElementById('threadName');
    let name = input.value.trim();
    let out = document.getElementById('outThread');
    let idDisp = document.getElementById('threadIdDisplay');
    let origText = btn.innerHTML;

    if (!name) {
        out.classList.add('show', 'error');
        out.textContent = '⚠️ 스레드 이름을 입력하세요.';
        return;
    }

    btn.disabled = true;
    btn.innerHTML = '<span class="spinner"></span> 생성 중...';

    try {
        const r = await apiPost('/api/create_thread', { name: name });
        out.classList.add('show');
        out.classList.remove('error');
        let txt = '';
        if (r.stdout) txt += r.stdout;
        if (r.stderr) txt += (txt ? '\n' : '') + r.stderr;
        if (!txt) txt = (r.ok ? '✅ 완료' : '❌ 실패') + ' (exit ' + r.code + ')';
        else txt += '\n--- [exit ' + r.code + '] ' + (r.ok ? '성공' : '실패') + ' ---';
        out.textContent = txt;

        // thread_id 추출 (출력에서 숫자 패턴 검색)
        if (r.ok && r.stdout) {
            let match = r.stdout.match(/(\d{15,20})/);
            if (match) {
                idDisp.classList.add('show');
                idDisp.textContent = 'Thread ID: ' + match[1];
            }
        }
        if (r.ok) input.value = '';
    } catch (e) {
        out.classList.add('show', 'error');
        out.textContent = '오류: ' + escapeHtml(e.message || e);
    } finally {
        btn.disabled = false;
        btn.innerHTML = origText;
    }
}

// ------------------------------------------------------------------
// 초기화 — 페이지 로드 즉시 상태 조회 및 10� 폴링 시작
// ------------------------------------------------------------------
updateStatus();
setInterval(updateStatus, 10000);
</script>

</body>
</html>
"""


# =============================================================================
# HTTP 요청 핸들러
# =============================================================================

class OrchestratorHandler(BaseHTTPRequestHandler):
    """오케스트레이터 웹 API + 정적 HTML 서빙 핸들러."""

    # 로그 포맷 (콘솔 출력 간소화)
    def log_message(self, format, *args):
        # 색상 없이 간단히: IP 없이 시간 + 요청줄만
        sys.stdout.write(
            "[%s] %s\n" % (time.strftime("%H:%M:%S"), args[0])
        )
        sys.stdout.flush()

    # ------------------------------------------------------------------
    # 응답 헬퍼
    # ------------------------------------------------------------------
    def _send_json(self, data, status=200):
        body = json.dumps(data, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def _send_html(self, html, status=200):
        body = html.encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def _send_text(self, text, status=200, content_type="text/plain; charset=utf-8"):
        body = text.encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _read_body(self):
        """요청 본문(JSON) 읽기. 딕셔너리 반환."""
        length = int(self.headers.get("Content-Length", 0) or 0)
        if length <= 0:
            return {}
        raw = self.rfile.read(length)
        try:
            return json.loads(raw.decode("utf-8"))
        except Exception:
            return {}

    # ------------------------------------------------------------------
    # GET 라우팅
    # ------------------------------------------------------------------
    def do_GET(self):
        path = urlparse(self.path).path

        if path == "/" or path == "/index.html":
            self._send_html(HTML_CONTENT)
            return

        if path == "/api/status":
            self._send_json(get_status())
            return

        if path == "/api/dns_check":
            self._send_json(api_dns_check())
            return

        if path == "/api/harness_status":
            self._send_json(api_harness_status())
            return

        # 알 수 없는 경로
        self._send_json({"error": "Not Found", "path": path}, status=404)

    # ------------------------------------------------------------------
    # POST 라우팅
    # ------------------------------------------------------------------
    def do_POST(self):
        path = urlparse(self.path).path

        if path == "/api/start":
            self._send_json(api_start_orchestrator())
            return

        if path == "/api/restart":
            self._send_json(api_restart_orchestrator())
            return

        if path == "/api/test_connection":
            self._send_json(api_test_connection())
            return

        if path == "/api/daily_report":
            self._send_json(api_daily_report())
            return

        if path == "/api/send_message":
            body = self._read_body()
            channel = body.get("channel", "")
            message = body.get("message", "")
            self._send_json(api_send_discord_message(channel, message))
            return

        if path == "/api/create_thread":
            body = self._read_body()
            name = body.get("name", "")
            self._send_json(api_create_thread(name))
            return

        # 알 수 없는 경로
        self._send_json({"error": "Not Found", "path": path}, status=404)


# =============================================================================
# 메인
# =============================================================================

def main():
    """웹 서버 시작."""
    server = ThreadingHTTPServer((HOST, PORT), OrchestratorHandler)
    server.daemon_threads = True

    # 시작 배너
    print("=" * 60)
    print("  Discord Orchestrator Web Server")
    print("=" * 60)
    print(f"  로컬:      http://localhost:{PORT}")
    print(f"  Tailscale: {TAILSCALE_URL}")
    print(f"  작업 디렉토리: {BASE_DIR}")
    print(f"  .env 로드: {'OK' if ENV else '없음/빈'}")
    print("=" * 60)
    print("  종료: Ctrl+C")
    print("=" * 60)
    print()

    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\n서버 종료 중...")
        server.shutdown()
        print("종료 완료.")


if __name__ == "__main__":
    main()