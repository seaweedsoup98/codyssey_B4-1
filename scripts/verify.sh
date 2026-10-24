#!/usr/bin/env bash
# Read-only verification commands for recording REAL evidence on the VM.
set -euo pipefail
[[ "$EUID" -eq 0 ]] || { echo 'Run with sudo to read all settings.' >&2; exit 1; }

printf '=== SSH effective configuration ===\n'
sshd -T -C user=root,host=localhost,addr=127.0.0.1 | grep -E '^(port|permitrootlogin) '
printf '\n=== Listening sockets ===\n'
ss -ltnp | grep -E ':20022|:15034' || true
printf '\n=== Firewall ===\n'
/usr/sbin/ufw status verbose || true
printf '\n=== Accounts and groups ===\n'
for user in agent-admin agent-dev agent-test; do id "$user"; done
printf '\n=== Directory ACLs ===\n'
getfacl -p /home/agent-admin /home/agent-admin/agent-app/{upload_files,api_keys,bin} /var/log/agent-app
printf '\n=== Monitor ownership ===\n'
stat -c '%U:%G %a %n' /home/agent-admin/agent-app/bin/monitor.sh
printf '\n=== Cron as agent-admin ===\n'
crontab -u agent-admin -l || true
printf '\n=== Latest monitor log ===\n'
tail -n 5 /var/log/agent-app/monitor.log || true
printf '\n=== Expected boot output ===\n'
printf 'Capture actual five [OK] checks and Agent READY separately when running the supplied app.\n'
