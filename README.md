# Codyssey B4-1 | Linux 서버 상태 관제

Linux 서버의 SSH/UFW 보안, 역할별 사용자·ACL, 제공 애플리케이션 실행 환경을 구성하고 **Bash `monitor.sh`**로 매분 상태를 수집합니다. **필수 항목만 구현**했으며 보너스 `report.sh` 및 7/30일 아카이브는 포함하지 않습니다.

## 파일

| 경로 | 역할 |
|---|---|
| [`bin/monitor.sh`](bin/monitor.sh) | 필수 제출 소스: Health Check, 방화벽 경고, CPU/MEM/DISK, 로그 10MB·10파일 관리 |
| [`docs/RESULTS.md`](docs/RESULTS.md) | 필수 제출 문서: 수행 내역, 검증 명령, 실제 확인/미확인 상태 |
| [`scripts/provision.sh`](scripts/provision.sh) | 계정, 그룹, 디렉토리, ACL, 환경 변수, 권한, cron 설정 |
| [`scripts/secure-network.sh`](scripts/secure-network.sh) | SSH 20022/Root 차단 및 UFW의 TCP 20022·15034만 허용 |
| [`scripts/install-app.sh`](scripts/install-app.sh) | 제공된 ZIP의 아키텍처별 공식 바이너리 설치 |
| [`scripts/run-app.sh`](scripts/run-app.sh) | 제공 앱을 `agent-admin`으로 실행 |
| [`scripts/verify.sh`](scripts/verify.sh) | 실제 VM 구성 증거를 읽어 출력 |
| [`tests/test_monitor.sh`](tests/test_monitor.sh) | Bash 기반 모의 테스트 9개 |
| [`docs/IMPLEMENTATION.md`](docs/IMPLEMENTATION.md) | 실행 순서·파일·함수·상태·설계 설명 |
| [`docs/CONCEPTS.md`](docs/CONCEPTS.md) | Linux/Bash/운영 개념과 코드 연결 |
| [`docs/EVALUATION.md`](docs/EVALUATION.md) | 예상 질문·핵심 답변·코드 위치 |

## 설치와 실행 (Ubuntu 22.04 LTS 실습 VM)

**중요:** SSH 포트와 방화벽을 변경하면 원격 접속이 끊길 수 있습니다. **콘솔 접근 가능한 독립 실습 VM**에서만 진행하고, `--apply` 전에 현재 SSH 접속을 대체할 비-Root 로그인 수단을 확보하세요. 기존 운영 서버에서 실행하지 마세요.

```bash
sudo apt-get update
sudo apt-get install -y openssh-server ufw acl sudo cron procps iproute2 util-linux unzip

git clone https://github.com/seaweedsoup98/codyssey_B4-1.git
cd codyssey_B4-1
sudo systemctl enable --now ssh cron
sudo bash scripts/provision.sh

# 콘솔에서만, 기존 UFW가 비활성인 새 실습 VM에 적용
sudo bash scripts/secure-network.sh --apply
```

제공된 **`agent-app.zip`**에는 `agent-app-linux-x86`(x86_64)과 `agent-app-linux-arm64`(aarch64)가 실제로 포함되어 있습니다. ZIP을 실습 VM의 저장소 최상위 폴더에 복사한 뒤 다음을 실행합니다. 실행 파일은 GitHub 공개 저장소에 재배포하지 않습니다.

```bash
# 위 provision.sh가 먼저 완료되어 있어야 함
sudo bash scripts/install-app.sh ./agent-app.zip
sudo -iu agent-admin /home/agent-admin/agent-app/bin/run-app.sh
```

**공식 바이너리의 확인된 호환성 차이:** 미션 문서의 `AGENT_KEY_PATH` 예시는 `.../api_keys/t_secret.key` **파일**을 지정하지만, 실제 제공된 실행 파일은 `.../api_keys` **디렉토리**와 내부 파일 `secret.key`를 요구합니다. `provision.sh`는 문서의 `t_secret.key`를 만든 뒤 `secret.key → t_secret.key` 심볼릭 링크를 추가하고, `run-app.sh`는 **바이너리 실행 시에만** 환경 변수를 디렉토리로 변경합니다. 제공 Python 파일 실행 경로에는 원래의 문서 설정을 유지합니다.

별도 터미널에서 다음을 검증합니다. 위 앱 실행은 종료하지 말고 유지합니다.

```bash
sudo -u agent-admin /home/agent-admin/agent-app/bin/monitor.sh
sudo bash scripts/verify.sh
sudo tail -n 5 /var/log/agent-app/monitor.log
sudo crontab -u agent-admin -l
# 약 1~2분 뒤 monitor.log 새 줄의 시각과 줄 수를 다시 비교
```

**완료 판정:** 앱의 Boot Sequence `[1/5]`~`[5/5]`가 모두 `[OK]`, `Agent READY`, `0.0.0.0:15034` LISTEN, `monitor.log`의 실제 누적, cron의 매분 실행을 확인해야 합니다. 실제 증거는 [`docs/RESULTS.md`](docs/RESULTS.md)에 반영합니다. 설치 스크립트 실행 자체만으로 완료라고 판단하지 않습니다.

## 개발 단계 검증

```bash
bash -n bin/monitor.sh scripts/*.sh tests/test_monitor.sh
bash tests/test_monitor.sh
```

`tests/test_monitor.sh`는 외부 명령을 모의하는 **로컬 기능 테스트**입니다. 별도로 이 ZIP의 x86_64 공식 앱을 Debian 13 격리 컨테이너에서 `agent-admin`으로 실행하여 **Boot 5/5 [OK], Agent READY, 0.0.0.0:15034 LISTEN, 실제 `monitor.sh` 로그 한 줄 기록**까지 확인했습니다. 이는 **Ubuntu 22.04 VM의 SSH/UFW/ACL/cron 적용 증거는 아닙니다**. 상세 결과는 [수행 내역](docs/RESULTS.md)에 적었습니다.

**추천 학습 순서:** [구현 흐름](docs/IMPLEMENTATION.md) → [핵심 개념](docs/CONCEPTS.md) → `bin/monitor.sh` → [평가 대비](docs/EVALUATION.md) → [수행 내역](docs/RESULTS.md).
