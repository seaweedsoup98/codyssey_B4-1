# B4-1 요구사항 수행 내역서

작성일: 2026-10-24. **대상 코드:** `seaweedsoup98/codyssey_B4-1`.

이 문서는 실제로 확인한 것과 실습 VM에서 **추가 확인해야 할 것**을 분리한다. 제공된 `B4-1.pdf`의 앱 자료 `agent-app.zip`은 현재 첨부되지 않았다. 따라서 실제 앱 부팅 성공, 실제 Ubuntu 방화벽, 계정/ACL과 cron의 자동 실행을 확인했다는 가짜 증거를 적지 않는다.

## 1. 구현 완료 내용(소스 기준)

| 요구사항 | 소스에서 구현한 방법 | 실습 VM 실측 |
|---|---|---|
| SSH TCP 20022, Root 접속 금지 | `scripts/secure-network.sh`의 `sshd` 설정과 사전 검증 | **미실시** |
| UFW 활성화, 허용 TCP 20022/15034만 | 동일 스크립트의 default deny 및 UFW 두 허용 규칙 | **미실시** |
| 계정 admin/dev/test, 그룹 common/core | `scripts/provision.sh`의 계정 생성 및 그룹 지정 | **미실시** |
| upload_files 공유, api_keys/log는 core 전용 | `provision.sh`의 디렉토리 소유권·2770·ACL 및 기본 ACL | **미실시** |
| 앱 환경 변수/키 | `agent-app.env` 생성, 실습 키 한 줄, `run-app.sh` | **미실시** (원본 앱 없음) |
| 앱 Boot 5×[OK], Agent READY | 제공 앱을 그대로 실행하도록 `run-app.sh` 구성 | **미실시** (원본 앱 없음) |
| 프로세스/포트 확인, 실패 시 exit 1 | `bin/monitor.sh`, PID 대조 | **모의 테스트+별도 실제 TCP 소켓 테스트 통과** |
| 방화벽 비활성 경고/리소스 수집/경고 | `bin/monitor.sh`, CPU>20/MEM>10/DISK>80 | **모의 테스트+별도 실제 리소스 수집 통과** |
| monitor.log 형식/최대 10MiB·10개 | 잠금, 로그 회전, 한 행 추가 | **모의 테스트 통과** |
| agent-admin cron 매분 실행 및 로그 증가 | `provision.sh`의 crontab 등록 | **실제 자동 실행 미실시** |

보너스 `report.sh`, 시간 기반 아카이브 정책은 제외했다. **날짜 기준 보존이 아니라 크기 기준 10MiB/10파일은 필수로 구현**했다.

## 2. 개발 환경에서 실제로 수행한 검증

- **실행 환경:** Debian GNU/Linux 13 격리 테스트 컨테이너. 요구 Ubuntu 22.04 실습 VM과 같지 않다.
- **정적 검사:** `bash -n bin/monitor.sh scripts/*.sh tests/test_monitor.sh` 통과.
- **모의 실행:** `bash tests/test_monitor.sh`의 **9개 확인 절차 통과**. 정상/임계값 같음, 프로세스 누락, 포트 누락, 타 프로세스 점유, UFW 비활성 경고, 세 임계값 초과, 로그 순환, 동시 잠금, 자원 수집 오류를 검증했다.
- **실제 시스템 명령 통합 확인:** 모의 소켓이 아닌 **테스트용** `python3 -m http.server`를 `agent-app-linux-x86` 프로세스 이름으로 TCP `0.0.0.0:15034`에 띄우고, 실제 `pgrep`·`ss`·`vmstat`·`free`·`df`와 `monitor.sh`를 실행했다. 로그 파일에 `PID`, `CPU`, `MEM`, `DISK_USED`가 기록됐으며 모드는 `660`이었다. 이 테스트 앱은 **공식 제공 앱이 아니며 Boot 5단계 증거가 아니다**.
- **실제 SSH/UFW/ACL/cron 적용:** 격리 개발 컨테이너에 운영 SSH 설정을 변경하지 않았다. 운영 서버에 영향을 미치는 명령을 실행한 것처럼 기록하지 않는다.

## 3. 실제 Ubuntu VM에서 수집해야 할 필수 증거

아래 명령을 실제 VM에 적용한 뒤 **출력/스크린샷을 첨부하고 결과를 기록**해야 공식 수행 내역이 완성된다. 경로와 계정은 `scripts/provision.sh`의 기본값이다.

| 확인 대상 | 명령 및 확인 포인트 | 상태 |
|---|---|---|
| SSH 유효 설정 | `sudo sshd -T -C user=root,host=localhost,addr=127.0.0.1 | grep -E '^(port|permitrootlogin) '` → `port 20022`, `permitrootlogin no` | 미확인 |
| SSH LISTEN | `sudo ss -ltnp | grep ':20022'` | 미확인 |
| UFW 활성/두 포트 | `sudo ufw status verbose` → 기본 inbound deny 및 20022/tcp·15034/tcp만 허용 | 미확인 |
| 사용자·그룹 | `id agent-admin; id agent-dev; id agent-test` → test는 core 미포함 | 미확인 |
| 디렉토리/ACL | `sudo getfacl -p /home/agent-admin/agent-app/{upload_files,api_keys} /var/log/agent-app` | 미확인 |
| monitor 소유·권한 | `sudo stat -c '%U:%G %a' /home/agent-admin/agent-app/bin/monitor.sh` → `agent-dev:agent-core 750` | 미확인 |
| 앱 Boot 성공 | `sudo -iu agent-admin /home/agent-admin/agent-app/bin/run-app.sh` → 실제 `[1/5]`~`[5/5] [OK]`, `Agent READY` 캡처 | 미확인 |
| 앱 LISTEN | `sudo ss -ltnp | grep ':15034'` → `0.0.0.0:15034` | 미확인 |
| 모니터 출력 | `sudo -u agent-admin /home/agent-admin/agent-app/bin/monitor.sh` → PID/PORT/CPU/MEM/DISK 및 경고 | 미확인 |
| 로그 누적 | `sudo tail -n 5 /var/log/agent-app/monitor.log` → 실제 로그 행 확인 | 미확인 |
| cron | `sudo crontab -u agent-admin -l` → `* * * * *` 작업 확인 | 미확인 |
| cron 자동 실행 | 앱 실행 중 1~2분 이후 `monitor.log`의 **새 타임스탬프/줄 수 증가** 확인 | 미확인 |

추가로 `sudo bash scripts/verify.sh`를 실행하면 SSH/소켓/UFW/계정/ACL/cron/최근 로그 상태를 한 번에 출력한다. 비밀 키 내용은 출력하지 않는다. 이 스크립트의 출력만으로 앱 Boot Sequence나 1분 후 자동 실행까지 증명되지는 않으므로 각각 따로 기록해야 한다.

## 4. 종료 조건과 남은 외부 작업

1. 공식 `agent-app.zip`의 원본 실행 파일을 확보하여 VM에 설치한다. 신뢰할 수 없는 타인의 빌드를 대체 사용하지 않는다.
2. 콘솔 접근 가능한 전용 Ubuntu 22.04 실습 VM에 `provision.sh`와 `secure-network.sh`를 적용한다. 새 터미널의 SSH 20022 접속을 확인한다.
3. 제공 앱의 실제 Boot 5단계와 `Agent READY`, 15034 LISTEN을 확인한다.
4. `monitor.sh` 직접 실행, 크론 등록, 1~2분 후 로그 증가를 확인한다.
5. 이 문서의 `미확인`을 실제 실행 증거와 함께 갱신한다. **그 전에는 실습 환경 검증 완료로 선언하지 않는다.**
