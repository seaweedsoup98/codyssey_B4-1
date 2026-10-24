#!/usr/bin/env bash
# DANGEROUS on remote servers: run only on a disposable VM with console access.
set -euo pipefail
if [[ "$EUID" -ne 0 || "${1:-}" != '--apply' || "$#" -ne 1 ]]; then
    echo 'At the VM console: sudo bash scripts/secure-network.sh --apply' >&2
    exit 1
fi
for command in sshd ufw ss systemctl; do
    command -v "$command" >/dev/null || { echo "Missing $command" >&2; exit 1; }
done
[[ -f /etc/ssh/sshd_config ]] || { echo 'Missing SSH server configuration.' >&2; exit 1; }

# Avoid quietly resetting an already active firewall on a reused server.
if ufw status | grep -qx 'Status: active'; then
    echo 'Existing active UFW rules found; use a fresh practice VM.' >&2
    exit 1
fi

config=/etc/ssh/sshd_config.d/00-codyssey-b4-1.conf
mkdir -p /etc/ssh/sshd_config.d
if [[ -e "$config" ]]; then
    echo "Refusing to overwrite $config; inspect it manually." >&2
    exit 1
fi
printf 'Port 20022\nPermitRootLogin no\n' > "$config"

rollback_ssh() {
    rm -f -- "$config"
    systemctl reload ssh || true
}
trap rollback_ssh ERR
sshd -t
ports=$(sshd -T | awk '$1 == "port" {print $2}')
root_login=$(sshd -T -C user=root,host=localhost,addr=127.0.0.1 | awk '$1 == "permitrootlogin" {print $2}')
[[ "$ports" == 20022 && "$root_login" == no ]] || {
    echo 'SSH has conflicting port/root-login settings; no firewall change applied.' >&2
    false
}
systemctl reload ssh
ss -H -ltn | awk '$4 ~ /(^|:)20022$/ {found=1} END {exit !found}' || {
    echo 'SSH is not listening on 20022; firewall was not enabled.' >&2
    false
}
trap - ERR

# Reset is intentional only on a fresh VM: UFW must permit exactly two inbound ports.
ufw --force reset
ufw default deny incoming
ufw default allow outgoing
ufw allow 20022/tcp
ufw allow 15034/tcp
ufw --force enable
ufw status verbose
printf 'Verify a NEW non-root SSH login on port 20022 before closing the console.\n'
