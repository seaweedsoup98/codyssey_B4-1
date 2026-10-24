#!/usr/bin/env bash
# Deterministic Bash tests. All external service/metric commands are mocked.
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
TEMP=$(mktemp -d)
trap 'rm -rf "$TEMP"' EXIT
mkdir -p "$TEMP/bin" "$TEMP/log"

cat > "$TEMP/bin/pgrep" <<'MOCK'
#!/usr/bin/env bash
[[ "${TEST_PROCESS:-ok}" != missing ]] || exit 1
printf '4242\n'
MOCK
cat > "$TEMP/bin/ss" <<'MOCK'
#!/usr/bin/env bash
[[ "${TEST_PORT:-ok}" != missing ]] || exit 0
pid=4242
[[ "${TEST_PORT:-ok}" != mismatch ]] || pid=9999
printf 'LISTEN 0 128 0.0.0.0:15034 0.0.0.0:* users:(("agent-app",pid=%s,fd=3))\n' "$pid"
MOCK
cat > "$TEMP/bin/sudo" <<'MOCK'
#!/usr/bin/env bash
[[ "${TEST_UFW:-active}" == active ]] || { printf 'Status: inactive\n'; exit 0; }
printf 'Status: active\n'
MOCK
cat > "$TEMP/bin/vmstat" <<'MOCK'
#!/usr/bin/env bash
[[ "${TEST_METRICS:-ok}" != fail ]] || exit 1
printf 'procs ----memory---- --cpu--\n'
printf 'r b swpd free buff cache si so bi bo in cs us sy id wa st\n'
printf '0 0 0 0 0 0 0 0 0 0 0 0 0 0 80 0 0\n'
printf '0 0 0 0 0 0 0 0 0 0 0 0 0 0 %s 0 0\n' "${TEST_IDLE:-80}"
MOCK
cat > "$TEMP/bin/free" <<'MOCK'
#!/usr/bin/env bash
printf '              total used free shared buff/cache available\n'
printf 'Mem:         1000 600 100 0 100 %s\n' "${TEST_AVAILABLE:-900}"
MOCK
cat > "$TEMP/bin/df" <<'MOCK'
#!/usr/bin/env bash
printf 'Filesystem 1024-blocks Used Available Capacity Mounted on\n'
printf 'mock        100 20 80 %s%% /\n' "${TEST_DISK:-80}"
MOCK
chmod +x "$TEMP/bin/"*

export AGENT_LOG_DIR="$TEMP/log"
export TEST_PROCESS=ok TEST_PORT=ok TEST_UFW=active TEST_METRICS=ok
export TEST_IDLE=80 TEST_AVAILABLE=900 TEST_DISK=80
PATH="$TEMP/bin:$PATH"; export PATH

run_monitor() {
    local code
    set +e
    output=$(/usr/bin/env bash "$ROOT/bin/monitor.sh" 2>&1)
    code=$?
    set -e
    return "$code"
}

pass() { printf '[PASS] %s\n' "$1"; }
count_lines() { wc -l < "$AGENT_LOG_DIR/monitor.log"; }

run_monitor || { echo "$output"; exit 1; }
[[ "$output" == *'PID: 4242'* ]] && {
    grep -Eq '^\[[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}\] PID:4242 CPU:20\.0% MEM:10\.0% DISK_USED:80%$' "$AGENT_LOG_DIR/monitor.log"
}
[[ "$output" != *'[WARNING]'* ]]
pass 'healthy status, exact thresholds (no warning), and log format'

export TEST_PROCESS=missing
if run_monitor; then echo 'Expected missing process to fail' >&2; exit 1; fi
[[ "$output" == *'[FAIL]'* && $(count_lines) -eq 1 ]]
pass 'missing process: exit 1 without a new sample'
export TEST_PROCESS=ok TEST_PORT=missing
if run_monitor; then echo 'Expected missing port to fail' >&2; exit 1; fi
[[ "$output" == *'not LISTENING'* && $(count_lines) -eq 1 ]]
pass 'missing LISTEN socket: exit 1'
export TEST_PORT=mismatch
if run_monitor; then echo 'Expected mismatched socket owner to fail' >&2; exit 1; fi
[[ "$output" == *'not owned by the application'* && $(count_lines) -eq 1 ]]
pass 'unrelated process on service port: exit 1'

export TEST_PORT=ok TEST_UFW=inactive
run_monitor
[[ "$output" == *'[WARNING] UFW is inactive'* && $(count_lines) -eq 2 ]]
pass 'inactive firewall: warn and keep logging'

export TEST_UFW=active TEST_IDLE=79 TEST_AVAILABLE=899 TEST_DISK=81
run_monitor
[[ "$output" == *'[WARNING] CPU threshold exceeded (21.0% > 20%)'* ]]
[[ "$output" == *'[WARNING] MEM threshold exceeded (10.1% > 10%)'* ]]
[[ "$output" == *'[WARNING] DISK_USED threshold exceeded (81% > 80%)'* ]]
[[ $(count_lines) -eq 3 ]]
pass 'all strict-above-threshold warnings; log still appended'

# Leave fewer than one line of headroom; rotate and retain nine archives.
truncate -s $((10 * 1024 * 1024 - 20)) "$AGENT_LOG_DIR/monitor.log"
for n in {1..9}; do printf 'archive-%s\n' "$n" > "$AGENT_LOG_DIR/monitor.log.$n"; done
run_monitor
[[ -f "$AGENT_LOG_DIR/monitor.log.1" && -f "$AGENT_LOG_DIR/monitor.log.9" ]]
[[ $(cat "$AGENT_LOG_DIR/monitor.log.9") == archive-8 ]]
[[ ! -e "$AGENT_LOG_DIR/monitor.log.10" ]]
[[ $(find "$AGENT_LOG_DIR" -maxdepth 1 -name 'monitor.log*' -type f | wc -l) -eq 10 ]]
[[ $(count_lines) -eq 1 ]]
pass '10 MiB boundary; active file plus nine rotated files'

exec 8>"$AGENT_LOG_DIR/.monitor.lock"
flock -n 8
if run_monitor; then echo 'Expected concurrent lock failure' >&2; exit 1; fi
[[ "$output" == *'previous monitor is still running'* ]]
flock -u 8
exec 8>&-
pass 'concurrent runs cannot interleave rotation and append'

export TEST_METRICS=fail
if run_monitor; then echo 'Expected metric collection failure' >&2; exit 1; fi
[[ "$output" == *'Cannot read CPU usage'* ]]
pass 'metric collection failure is reported'

printf '\n9 checks passed.\n'
