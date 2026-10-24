#!/usr/bin/env bash
# Runs every minute as agent-admin. Exit 1 only for failed health checks/errors.
set -euo pipefail
export LC_ALL=C
umask 007

AGENT_PORT="${AGENT_PORT:-15034}"
AGENT_LOG_DIR="${AGENT_LOG_DIR:-/var/log/agent-app}"
LOG_FILE="$AGENT_LOG_DIR/monitor.log"
MAX_BYTES=10000000  # 10 MB (decimal bytes)
# Accept both the supplied Linux binaries and the Python app mentioned in the PDF.
PROCESS_PATTERN='(^|[ /])(agent_app\.py|agent-app-linux-(x86|arm64)|agent-app)([[:space:]]|$)'

fail() {
    printf '[FAIL] %s\n' "$*" >&2
    exit 1
}

printf '====== SYSTEM MONITOR RESULT ======\n\n[HEALTH CHECK]\n'
mapfile -t pids < <(pgrep -u "$(id -u)" -f "$PROCESS_PATTERN" || true)
((${#pids[@]} > 0)) || fail 'Application process is not running.'

# A listening socket must belong to one of the matching application processes.
listeners=$(ss -H -ltnp "sport = :$AGENT_PORT") || fail 'Cannot inspect TCP sockets.'
[[ -n "$listeners" ]] || fail "TCP $AGENT_PORT is not LISTENING."
pid=''
for candidate in "${pids[@]}"; do
    if [[ "$listeners" == *"pid=$candidate,"* ]]; then
        pid="$candidate"
        break
    fi
done
[[ -n "$pid" ]] || fail "TCP $AGENT_PORT is not owned by the application."
printf 'Process... [OK] (PID: %s)\nPort %s/tcp... [OK]\n' "$pid" "$AGENT_PORT"

printf '\n[FIREWALL]\n'
if sudo -n /usr/sbin/ufw status 2>/dev/null | grep -qx 'Status: active'; then
    printf 'UFW... [OK]\n'
else
    printf '[WARNING] UFW is inactive or its status cannot be read.\n'
fi

printf '\n[RESOURCE MONITORING]\n'
# Second vmstat row is a one-second sample, not the since-boot average.
cpu=$(vmstat 1 2 | awk 'END {if (NR < 4 || $15 == "") exit 1; printf "%.1f", 100 - $15}') || fail 'Cannot read CPU usage.'
# MemAvailable counts memory reclaimable by the kernel, unlike the raw "used" column.
mem=$(free -b | awk '/^Mem:/ {if ($2 <= 0 || $7 == "") exit 1; printf "%.1f", 100 * ($2 - $7) / $2; found=1} END {if (!found) exit 1}') || fail 'Cannot read memory usage.'
disk=$(df -P / | awk 'NR == 2 {gsub(/%/, "", $5); if ($5 !~ /^[0-9]+$/) exit 1; print $5; found=1} END {if (!found) exit 1}') || fail 'Cannot read root disk usage.'
printf 'CPU Usage : %s%%\nMEM Usage : %s%%\nDISK Used : %s%%\n' "$cpu" "$mem" "$disk"

warn_if_high() {
    if awk -v value="$2" -v limit="$3" 'BEGIN {exit !(value > limit)}'; then
        printf '[WARNING] %s threshold exceeded (%s%% > %s%%)\n' "$1" "$2" "$3"
    fi
}
warn_if_high CPU "$cpu" 20
warn_if_high MEM "$mem" 10
warn_if_high DISK_USED "$disk" 80

# Only one cron/manual run may rotate and append to the log at a time.
[[ -d "$AGENT_LOG_DIR" && -w "$AGENT_LOG_DIR" ]] || fail "Cannot write to $AGENT_LOG_DIR."
exec 9>"$AGENT_LOG_DIR/.monitor.lock" || fail 'Cannot open log lock.'
flock -n 9 || fail 'A previous monitor is still running.'
[[ ! -L "$LOG_FILE" ]] || fail 'Refusing a symbolic-link log file.'
[[ ! -e "$LOG_FILE" || -f "$LOG_FILE" ]] || fail 'Log path is not a regular file.'

line=$(printf '[%s] PID:%s CPU:%s%% MEM:%s%% DISK_USED:%s%%' \
    "$(date '+%Y-%m-%d %H:%M:%S')" "$pid" "$cpu" "$mem" "$disk")
size=0
if [[ -f "$LOG_FILE" ]]; then
    size=$(stat -c %s "$LOG_FILE") || fail 'Cannot read log size.'
fi

# 10 files total: active monitor.log plus monitor.log.1 through .9.
if ((size + ${#line} + 1 > MAX_BYTES)); then
    rm -f -- "$LOG_FILE.9"
    for ((i = 8; i >= 1; i--)); do
        if [[ -f "$LOG_FILE.$i" ]]; then
            mv -f -- "$LOG_FILE.$i" "$LOG_FILE.$((i + 1))"
        fi
    done
    if [[ -f "$LOG_FILE" ]]; then
        mv -f -- "$LOG_FILE" "$LOG_FILE.1"
    fi
fi
printf '%s\n' "$line" >> "$LOG_FILE" || fail 'Cannot append monitor log.'
printf '\n[INFO] Log appended: %s\n' "$LOG_FILE"
