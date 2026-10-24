# 구현 해설: 서버 설정부터 매분 로그 기록까지

## 1. 전체 실행 흐름

```text
[관리자, 최초 1회]
provision.sh ─→ 계정·그룹 ─→ ACL/디렉토리 ─→ env/키 ─→ 스크립트 배치 ─→ cron
secure-network.sh ─→ SSH 20022/Root 차단 ─→ SSH 재검증 ─→ UFW 두 포트 허용
            ↓
[agent-admin, 서비스 실행]
run-app.sh ─→ agent-app.env ─→ 제공 바이너리/agent_app.py 실행
            ↓
[agent-admin, 매분 cron]
monitor.sh ─→ 프로세스 확인 ─→ 15034 포트/소유 PID 확인
           ─→ UFW 상태(경고) ─→ CPU/MEM/DISK 수집·경고
           ─→ 동시 실행 잠금 ─→ 필요 시 로그 회전 ─→ monitor.log 추가
```

최초 설정은 Root 권한이 필요하지만, 실제 앱과 모니터링 작업은 **일반 계정 `agent-admin`**으로 실행합니다. 제공 앱 파일이 없으면 실행 단계부터 멈추므로 실제 Boot Sequence는 확인할 수 없습니다.

## 2. `scripts/provision.sh`: 권한과 실행 기반 마련

1. `groupadd`/`useradd`로 `agent-common`(admin/dev/test)과 `agent-core`(admin/dev) 구성. `agent-test`가 이미 core에 속해 있으면 제거합니다.
2. `/home/agent-admin`은 일반 사용자가 볼 수 없도록 700으로 제한한 뒤 ACL `g:agent-common:--x`를 부여합니다. 따라서 공유 영역에 **진입**은 가능하지만 홈 디렉토리 목록은 볼 수 없습니다.
3. `$AGENT_HOME`은 `2710`: 소유자 전체 권한, 공통 그룹 진입만 허용. `upload_files`는 `agent-common`, `api_keys`와 `/var/log/agent-app`는 `agent-core`의 2770 디렉토리입니다. 구 ACL을 초기화하고 named/default ACL을 설정해 새 파일에도 그룹 접근을 유지합니다.
4. `t_secret.key`에 실습에서 지정한 한 줄을 저장하고 660(`agent-admin:agent-core`)을 부여합니다. 기존 키 값이 다르면 덮어쓰지 않고 오류로 종료합니다.
5. `agent-app.env`에 다섯 환경 변수의 실제 경로를 기록하고 `/etc/profile.d/agent-app.sh`에서 `agent-admin` 로그인 시 읽습니다. cron은 로그인 셸을 거치지 않으므로 `monitor.sh`가 포트와 로그 디렉토리에 기본값을 갖습니다.
6. `monitor.sh`를 `agent-dev:agent-core` **750**으로 설치합니다. 소유자는 수정할 수 있고, `agent-admin`은 그룹의 읽기·실행 권한으로 실행할 수 있습니다. `run-app.sh`는 `agent-admin`이 소유합니다.
7. `agent-admin`에게 **읽기 전용** `sudo -n /usr/sbin/ufw status`만 무암호 허용합니다. `agent-admin`의 기존 crontab은 유지하고 매분 실행 한 줄만 추가합니다.

> 사용한 그룹·소유권은 Linux VM에 실제 적용해야 효력이 있습니다. Git 저장소에 스크립트가 들어 있다는 사실만으로 적용되지는 않습니다.

## 3. `scripts/secure-network.sh`: 위험한 네트워크 변경 분리

`--apply`를 명시한 Root 호출만 실행합니다. 기존 UFW가 이미 활성 상태면 실수로 운영 규칙을 초기화하지 않도록 중단합니다. SSH drop-in을 만든 뒤 `sshd -t`(문법)와 `sshd -T`(유효 설정)로 **오직 20022와 `PermitRootLogin no`**인지 점검합니다. SSH 리로드 후 20022 LISTEN 상태를 확인해야 UFW 기본 인바운드 차단과 20022/tcp·15034/tcp 허용을 적용합니다. SSH 검증 실패 시 drop-in을 제거하도록 오류 트랩을 둡니다.

SSH 설정 변경은 현재 터미널이 아닌 **새 터미널에서 포트 20022 비-Root 로그인**에 성공했을 때만 성공입니다. 콘솔 접근 없는 원격 서버에는 적용하지 마세요.

## 4. `scripts/run-app.sh`: 제공 앱 실행

1. `id -un`과 `EUID`로 실행자가 `agent-admin`인 일반 사용자인지 확인합니다.
2. `agent-app.env`를 `source`하여 `AGENT_HOME`, `AGENT_PORT=15034`, `AGENT_UPLOAD_DIR`, `AGENT_KEY_PATH`, `AGENT_LOG_DIR`를 **자식 프로세스에 전달**합니다.
3. `uname -m`에 따라 공식 패키지의 `agent-app-linux-x86` 또는 `agent-app-linux-arm64`를 선택합니다. 제공 자료가 `agent_app.py`라면 Python으로 실행합니다.
4. `exec`는 셸을 앱 프로세스로 교체합니다. 덕분에 앱 종료 신호(Ctrl+C)를 앱에 전달하며 PID가 불필요하게 늘지 않습니다.

앱 내부 부팅 점검은 프로젝트 코드가 구현한 것이 아니라 **제공 앱이 수행**합니다. 임의의 `[OK]` 출력을 만들어 성공을 대신하지 않습니다.

## 5. `bin/monitor.sh`: 매분 실제 처리 순서

| 단계 | 코드와 실제 동작 | 실패 처리 |
|---|---|---|
| 실행 준비 | `set -euo pipefail`, `LC_ALL=C`, 기본값과 임계값 선언 | 일반 실행 오류는 종료 |
| 프로세스 | `pgrep -u "$(id -u)" -f ...`로 같은 계정의 제공 앱 PID 목록 수집 | 없으면 `[FAIL]`, `exit 1` |
| 포트 | `ss -H -ltnp "sport = :15034"`로 LISTEN 및 **앱과 동일한 PID** 확인 | 없거나 다른 프로세스가 점유하면 `exit 1` |
| 방화벽 | 제한된 sudo 명령으로 `Status: active` 확인 | 미활성/조회 불가 시 `[WARNING]`, 계속 |
| CPU | `vmstat 1 2`의 두 번째 샘플에서 `100 - idle(%)` | 수집 불가 시 오류 종료 |
| 메모리 | `free -b`에서 `(MemTotal - MemAvailable)/MemTotal × 100` | 수집 불가 시 오류 종료 |
| 디스크 | `df -P /`에서 루트 파일시스템 `Use%` | 수집 불가 시 오류 종료 |
| 임계값 | Bash 함수 `warn_if_high`, `awk` 부동소수점 비교 | CPU>20, MEM>10, DISK>80이면 경고만 |
| 기록 | `flock`을 이용한 잠금 후 필요 시 로그 회전 및 `printf >> monitor.log` | 쓰기·잠금 오류는 종료 |

`pgrep`만 쓰면 앱이 살아 있어도 **다른 프로세스**가 15034를 차지한 경우를 놓칠 수 있습니다. 따라서 `ss -p`에 표시된 소켓 소유 PID까지 비교합니다. 일반 계정에서 자신이 소유한 소켓의 PID를 읽을 수 있어야 하며, 보안 정책이 이를 숨기면 보수적으로 실패합니다.

### 로그 순환 규칙

- 로그 형식: `[YYYY-MM-DD HH:MM:SS] PID:n CPU:n% MEM:n% DISK_USED:n%`.
- 한 행을 추가했을 때 활성 파일이 **10MiB(10×1024×1024바이트)**를 넘는다면 먼저 회전합니다.
- 기존 `.9` 삭제 → `.8`부터 `.1`까지 번호 +1 → 기존 활성 로그를 `.1`로 이동 → 새 활성 로그에 기록합니다.
- 보관 파일은 `monitor.log`와 `.1`~`.9`까지 **최대 10개**입니다. 보너스의 날짜 기준 압축/삭제와는 무관합니다.
- `flock`은 수동 실행과 cron이 겹쳐 로그가 엉키는 것을 막습니다. 회전·기록 실패를 성공으로 보고하지 않습니다.

### cron과 로그가 다르게 보이는 이유

crontab의 `* * * * *`는 매분 실행하라는 뜻입니다. 이 작업의 표준 출력과 오류는 `cron.log`로 가지만, **정상 모니터링 수치**는 `monitor.sh`가 별도로 `monitor.log`에 직접 추가합니다. 앱이 꺼지면 Health Check가 실패해 `cron.log`에 오류가 나타나고 정상 수치 행은 추가되지 않습니다.

## 6. 설계상의 선택과 한계

- **Bash만 사용:** `/proc`를 직접 파싱하는 복잡한 구현 대신 Ubuntu 기본 명령(`pgrep`, `ss`, `vmstat`, `free`, `df`, `flock`)을 사용해 학습자가 각 명령을 터미널에서 다시 검증할 수 있습니다.
- **복구 기능 없음:** 미션은 관제·기록이지 앱 자동 재시작이 아니므로 추가하지 않았습니다.
- **모의 테스트와 실제 VM 구분:** `tests/test_monitor.sh`는 입력·경계·오류 동작을 검증합니다. SSH, UFW, ACL, 앱 Boot Sequence, crontab의 실효성은 실제 Ubuntu VM에서 다시 확인해야 합니다.
