# Discord 워커 봇 스레드 권한 설정 가이드
# ============================================================
# 작성일: 2026-08-01
# 문제: 워커 봇(CL-Worker, codex-worker, Gm-Worker)이 #작업 스레드에 메시지 게시 불가 (403)
# 원인: 워커 봇 역할에 "Send Messages in Threads" 권한이 없음
# ------------------------------------------------------------

## 문제 요약
- 워커 봇은 #작업 채널 직접 게시: OK (HTTP 200)
- 워커 봇은 #수다 채널 직접 게시: OK (HTTP 200)
- 워커 봇은 #작업 스레드 안에 게시: FAIL (HTTP 403)
- ORCH 봇은 스레드 생성자라 스레드 게시 가능

## 원인
Discord 권한 "Send Messages in Threads" (0x40000)이 워커 봇 역할에 없음:
- @everyone: send_messages_in_threads = True
- CL-Worker 역할: send_messages_in_threads = False
- codex-worker 역할: send_messages_in_threads = False
- Gm-Worker 역할: send_messages_in_threads = False
- Orchestrator 역할: send_messages_in_threads = False

Orchestrator 봇은 스레드를 생성한 봇이라 자동으로 스레드 권한을 가지지만,
워커 봇은 스레드 생성자가 아니라서 권한이 필요합니다.

## 해결 방법 (Discord 서버 설정에서 수동)

### 방법 1: 각 워커 역할에 권한 추가
1. Discord 서버 설정 → 역할(Roles)
2. 각 워커 봇 역할 선택:
   - CL-Worker
   - codex-worker
   - Gm-Worker
3. 각 역할의 권한에서 "Send Messages in Threads" 켜기

### 방법 2: 서버 전체 설정
1. Discord 서버 설정 → 역할 → @everyone
2. "Send Messages in Threads"가 이미 True인지 확인
3. 워커 봇 역할들이 @everyone 권한을 상속하는지 확인
4. 안 되면 각 워커 역할에 직접 추가

### 방법 3: ORCH 봇에 관리자 권한 부여 (간편)
1. Discord 서버 설정 → 역할 → Orchestrator
2. "Manage Roles" 또는 "Administrator" 켜기
3. ORCH 봇이 자동으로 워커 봇 권한을 관리 가능

## 검증
권한 변경 후:
1. #작업 스레드에 워커 봇이 메시지를 보낼 수 있는지 테스트
2. post-as.sh claude <thread_id> "테스트" 실행
3. HTTP 200이면 성공

## Discord 서버 정보
- Guild ID: 1232220575187861554
- #작업 채널 ID: 1531495731167494194
- 봇 역할 ID:
  - Orchestrator: 1531497443827515548
  - codex-worker: 1531498039120756821
  - Gm-Worker: 1531521566838362214
  - CL-Worker: 1531523049604649044
