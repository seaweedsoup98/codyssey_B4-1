# B4-1 요구사항 수행 내역서

작성일: 2026-10-24. **대상 코드:** `seaweedsoup98/codyssey_B4-1`.

실제로 검증한 **공식 x86_64 앱의 실행**, Bash 모의 테스트와 **실제 Ubuntu 실습 VM에서 아직 수행하지 못한 설정**을 구분한다. 사용자 제공 `agent-app.zip`(2026-10-24)을 검사했고 그 안의 x86/ARM64 실행 파일을 확인했다. 앱 자체는 Debian 13 격리 컨테이너에서 일반 계정으로 구동했으며 **Ubuntu 22.04의 SSH/UFW/ACL/cron까지 적용했다는 뜻은 아니다**.

## 1. 구현 완료 내용(소스 기준)

| 요구사항 | 소스에서 구현한 방법 | 실습 VM 실측 |
|---|---|---|
| SSH TCP 20022, Root 접속 금지 | `scripts/secure-network.sh`의 `sshd` 설정과 사전 검증 | **미실시** |
| UFW 활성화, 허용 TCP 20022/15034만 | 동일 스크립트의 default deny 및 UFW 두 허용 규칙 | **미실시** |
| 계정 admin/dev/test, 그룹 common/core | `scripts/provision.sh`의 계정 생성 및 그룹 지정 | **미실시** |
| upload_files 공유, api_keys/log는 core 전용 | `provision.sh`의 디렉토리 소유권·2770·ACL 및 기본 ACL | **미실시** |
| 앱 환경 변수/키 | `agent-app.env` 생성, 실습 키 한 줄, `secret.key` 호환 링크와 바이너리용 키 디렉토리 설정 | **x86 공식 바이너리에서 5/5 통과** |
| 앱 Boot 5×[OK], Agent READY | `install-app.sh`로 ZIP 원본 설치, `run-app.sh` 일반 계정 실행 | **Debian 13 x86_64 격리 컨테이너 실측 성공** |
| 프로세스/포트 확인, 실패 시 exit 1 | `bin/monitor.sh`, PID 대조 | **모의 테스트 + 공식 앱 실시간 연동 통과** |
| 방화벽 비활성 경고/리소스 수집/경고 | `bin/monitor.sh`, CPU>20/MEM>10/DISK>80 | **모의 테스트 + 공식 앱 연동에서 경고·실측 성공** |
| monitor.log 형식/최대 10MB·10개 | 잠금, 로그 회전, 한 행 추가 | **공식 앱 로그 한 줄 기록 + 10개 파일 회전 모의 테스트 통과** |
| agent-admin cron 매분 실행 및 로그 증가 | `provision.sh`의 crontab 등록 | **실제 자동 실행 미실시** |

보너스 `report.sh`, 시간 기반 아카이브 정책은 제외했다. **날짜 기준 보존이 아니라 크기 기준 10MB/10파일은 필수로 구현**했다.

## 2. 실제로 수행한 검증

- **실행 환경:** Debian GNU/Linux 13 격리 컨테이너, x86_64. Ubuntu 22.04 실습 VM이 아니다.
- **공식 업로드 ZIP:** `agent-app-linux-x86`(ELF x86_64, 6,498,144바이트), `agent-app-linux-arm64`(ELF aarch64, 7,537,848바이트). ZIP SHA-256: `b0489f1035369b4a8785cd84f2f0ff99f2b04f76d4caa1eca07229abb48a7732`.
- **설치 검증:** `bash scripts/install-app.sh /mnt/data/agent-app.zip`를 두 번 실행하여 내용 동일한 바이너리 설치·재실행에 모두 성공. 설치 바이너리 SHA-256: `cdbae8c066e734916b7cd25dc9e651818acf63b2e6817125ede5e85a4de0ff5a`, 소유·권한 `agent-admin:agent-core 750`. ZIP 누락 시 종료 코드 1 확인.
- **Bash 정적 검사:** `bash -n bin/monitor.sh scripts/*.sh tests/test_monitor.sh` 통과.
- **Bash 모의 테스트:** `bash tests/test_monitor.sh` **9개 통과**(정상 및 정확한 임계값, 프로세스 없음, 포트 없음, 타 PID 소켓, 비활성 방화벽 경고, 임계값 초과, 10MB/10개 회전, 동시 실행 잠금, 지표 수집 오류).
- **실제 앱 연동:** 공식 x86_64 바이너리를 `agent-admin` 일반 계정으로 실행. 처음에는 PDF와 바이너리의 키 경로 형식이 달라 실패했고, **디렉토리 환경 변수 + `secret.key` 링크**를 적용한 뒤 5단계 모두 통과. 실제 `ss`에서 `0.0.0.0:15034` LISTEN 확인. 이 실행 중 `monitor.sh`를 `agent-admin`으로 실행하여 정상 종료(코드 0), PID 확인, 실제 자원 데이터·경고·`monitor.log` 한 줄 기록 확인.
- **미실시:** 실제 SSH 20022·UFW 규칙 적용, ACL과 crontab 등록/자동실행, ARM64 앱 실행. 컨테이너에서 위험한 네트워크 설정을 변경하지 않았다.

### 공식 x86_64 앱 Boot 출력에서 확인한 항목

```text
>>> Starting Agent Boot Sequence...
[1/5] Checking User Account               [OK]
[2/5] Verifying Environment Variables     [OK]
[3/5] Checking Required Files             [OK]
[4/5] Checking Port Availability          [OK]
[5/5] Verifying Log Permission            [OK]
All Boot Checks Passed!
Agent READY
```

### 실제 앱의 소켓·모니터링·로그 (컨테이너 실측)

```text
LISTEN 0 0 0.0.0.0:15034 0.0.0.0:*
[HEALTH CHECK]
Process... [OK] (PID: 2072)
Port 15034/tcp... [OK]
[FIREWALL]
[WARNING] UFW is inactive or its status cannot be read.
[RESOURCE MONITORING]
CPU Usage : 6.0%
MEM Usage : 20.2%
DISK Used : 1%
[WARNING] MEM threshold exceeded (20.2% > 10%)
[INFO] Log appended: /var/log/agent-app/monitor.log
```

`/var/log/agent-app/monitor.log`에 추가된 실제 한 줄:

```text
[2026-10-24 06:36:43] PID:2072 CPU:6.0% MEM:20.2% DISK_USED:1%
```

이 출력은 **시험 당시 관측한 값**으로, 다른 환경의 PID·자원 사용률과 일치해야 하는 고정 예상 출력이 아니다. 표시 시각은 컨테이너의 UTC이다.

### PDF 예시와 제공 바이너리의 호환성

PDF는 `AGENT_KEY_PATH=$AGENT_HOME/api_keys/t_secret.key`를 안내한다. 업로드된 바이너리에 동일한 경로를 넘기면 `[2/5]`에서 `Key Path Mismatch. Expected: /home/agent-admin/agent-app/api_keys`라고 종료한다. 바이너리에는 `AGENT_KEY_PATH=$AGENT_HOME/api_keys`를 전달해야 하고, 그다음 `[3/5]`에서 `secret.key`를 읽는다. 미션의 `t_secret.key`를 유지하면서 바이너리를 통과시키기 위해 `provision.sh`가 `secret.key -> t_secret.key` 상대 링크를 생성하며 `run-app.sh`가 바이너리 실행에 한해 키 디렉토리를 전달한다.

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
| 앱 Boot 성공 (VM) | `sudo -iu agent-admin /home/agent-admin/agent-app/bin/run-app.sh` → 실제 `[1/5]`~`[5/5] [OK]`, `Agent READY` 캡처 | Debian x86 확인, Ubuntu VM 미확인 |
| 앱 LISTEN (VM) | `sudo ss -ltnp | grep ':15034'` → `0.0.0.0:15034` | Debian x86 확인, Ubuntu VM 미확인 |
| 모니터 출력 (VM) | `sudo -u agent-admin /home/agent-admin/agent-app/bin/monitor.sh` → PID/PORT/CPU/MEM/DISK 및 경고 | Debian x86 확인, Ubuntu VM 미확인 |
| 로그 누적 (VM) | `sudo tail -n 5 /var/log/agent-app/monitor.log` → 실제 로그 행 확인 | Debian 수동 한 줄 확인, Ubuntu VM 미확인 |
| cron | `sudo crontab -u agent-admin -l` → `* * * * *` 작업 확인 | 미확인 |
| cron 자동 실행 | 앱 실행 중 1~2분 이후 `monitor.log`의 **새 타임스탬프/줄 수 증가** 확인 | 미확인 |

추가로 `sudo bash scripts/verify.sh`를 실행하면 SSH/소켓/UFW/계정/ACL/cron/최근 로그 상태를 한 번에 출력한다. 비밀 키 내용은 출력하지 않는다. 이 스크립트의 출력만으로 앱 Boot Sequence나 1분 후 자동 실행까지 증명되지는 않으므로 각각 따로 기록해야 한다.

## 4. 종료 조건과 남은 외부 작업

1. 사용자에게 받은 `agent-app.zip`을 전용 Ubuntu 22.04 실습 VM의 저장소 폴더에 복사한다. `sudo bash scripts/provision.sh` 뒤 `sudo bash scripts/install-app.sh ./agent-app.zip`으로 아키텍처별 바이너리를 설치한다.
2. 콘솔 접근이 가능한 VM에서만 `sudo bash scripts/secure-network.sh --apply`를 실행하고, 새 터미널에서 SSH 20022의 비-Root 로그인 성공을 확인한다. 현재 연결을 먼저 닫지 않는다.
3. VM에서 제공 앱의 5단계와 `Agent READY`, 15034 LISTEN을 다시 확인한다.
4. `monitor.sh`를 직접 실행하고, cron 등록 후 1~2분 동안 **자동으로** `monitor.log`가 증가하는지 비교한다.
5. 위 표의 미확인 항목을 실제 VM에서 얻은 출력과 함께 기록한다. **그 전에는 Ubuntu 실습 환경의 전체 요구사항을 검증 완료로 선언하지 않는다.**
