#!/usr/bin/env bash
# Prepare users, ACLs, environment and cron on a dedicated Ubuntu practice VM.
set -euo pipefail

[[ "$EUID" -eq 0 ]] || { echo 'Run with sudo.' >&2; exit 1; }
for command in groupadd useradd usermod gpasswd setfacl getent install crontab; do
    command -v "$command" >/dev/null || { echo "Missing command: $command" >&2; exit 1; }
done

REPO_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
AGENT_HOME=/home/agent-admin/agent-app
LOG_DIR=/var/log/agent-app
KEY_FILE="$AGENT_HOME/api_keys/t_secret.key"
KEY_LINK="$AGENT_HOME/api_keys/secret.key"

# Do not overwrite an existing secret or follow a symlink into another file.
if [[ -e "$KEY_FILE" || -L "$KEY_FILE" ]]; then
    [[ -f "$KEY_FILE" && ! -L "$KEY_FILE" ]] || { echo 'Unsafe existing key file.' >&2; exit 1; }
    cmp -s <(printf 'agent_api_key_test\n') "$KEY_FILE" || { echo 'Existing key has different contents.' >&2; exit 1; }
fi
# The supplied frozen app also looks for api_keys/secret.key. Check any
# pre-existing link before proceeding; never replace an unrelated file.
if [[ -e "$KEY_LINK" || -L "$KEY_LINK" ]]; then
    [[ -L "$KEY_LINK" && $(readlink -- "$KEY_LINK") == t_secret.key ]] || {
        echo 'Unsafe existing secret.key compatibility link.' >&2; exit 1;
    }
fi

getent group agent-common >/dev/null || groupadd agent-common
getent group agent-core >/dev/null || groupadd agent-core
for user in agent-admin agent-dev agent-test; do
    id "$user" >/dev/null 2>&1 || useradd -m -s /bin/bash "$user"
done
usermod -aG agent-common,agent-core agent-admin
usermod -aG agent-common,agent-core agent-dev
usermod -aG agent-common agent-test
if id -nG agent-test | grep -qw agent-core; then
    gpasswd -d agent-test agent-core
fi

# Clear pre-existing ACLs so old permissions cannot bypass the new policy.
setfacl -b /home/agent-admin
setfacl -k /home/agent-admin
chmod 700 /home/agent-admin
setfacl -m g:agent-common:--x /home/agent-admin
install -d -o agent-admin -g agent-common -m 2710 "$AGENT_HOME"
install -d -o agent-admin -g agent-common -m 2770 "$AGENT_HOME/upload_files"
install -d -o agent-admin -g agent-core -m 2770 "$AGENT_HOME/api_keys"
install -d -o agent-dev -g agent-core -m 2750 "$AGENT_HOME/bin"
install -d -o agent-admin -g agent-core -m 2770 "$LOG_DIR"
for directory in "$AGENT_HOME" "$AGENT_HOME/upload_files" "$AGENT_HOME/api_keys" "$AGENT_HOME/bin" "$LOG_DIR"; do
    setfacl -b "$directory"
    setfacl -k "$directory"
done

# Named and default ACL entries preserve group access on future files.
setfacl -m g:agent-common:rwx,d:g:agent-common:rwx,d:m::rwx,d:o::--- "$AGENT_HOME/upload_files"
setfacl -m g:agent-core:rwx,d:g:agent-core:rwx,d:m::rwx,d:o::--- "$AGENT_HOME/api_keys" "$LOG_DIR"

if [[ ! -e "$KEY_FILE" ]]; then
    (umask 077; printf 'agent_api_key_test\n' > "$KEY_FILE")
fi
chown agent-admin:agent-core "$KEY_FILE"
chmod 660 "$KEY_FILE"
if [[ ! -L "$KEY_LINK" ]]; then
    ln -s t_secret.key "$KEY_LINK"
fi

cat > "$AGENT_HOME/agent-app.env" <<'ENV'
export AGENT_HOME=/home/agent-admin/agent-app
export AGENT_PORT=15034
export AGENT_UPLOAD_DIR="$AGENT_HOME/upload_files"
export AGENT_KEY_PATH="$AGENT_HOME/api_keys/t_secret.key"
export AGENT_LOG_DIR=/var/log/agent-app
ENV
chown agent-admin:agent-core "$AGENT_HOME/agent-app.env"
chmod 640 "$AGENT_HOME/agent-app.env"

cat > /etc/profile.d/agent-app.sh <<'PROFILE'
if [ "$(id -un)" = agent-admin ] && [ -r /home/agent-admin/agent-app/agent-app.env ]; then
    . /home/agent-admin/agent-app/agent-app.env
fi
PROFILE
chmod 644 /etc/profile.d/agent-app.sh

install -o agent-dev -g agent-core -m 750 "$REPO_DIR/bin/monitor.sh" "$AGENT_HOME/bin/monitor.sh"
install -o agent-admin -g agent-core -m 750 "$REPO_DIR/scripts/run-app.sh" "$AGENT_HOME/bin/run-app.sh"
if [[ ! -e "$LOG_DIR/monitor.log" ]]; then
    install -o agent-admin -g agent-core -m 660 /dev/null "$LOG_DIR/monitor.log"
fi
[[ ! -L "$LOG_DIR/monitor.log" ]] || { echo 'Unsafe monitor.log symlink.' >&2; exit 1; }
chown agent-admin:agent-core "$LOG_DIR/monitor.log"
chmod 660 "$LOG_DIR/monitor.log"

# sudo only permits the read-only firewall status command to run noninteractively.
cat > /etc/sudoers.d/agent-monitor <<'SUDOERS'
agent-admin ALL=(root) NOPASSWD: /usr/sbin/ufw status
SUDOERS
chmod 440 /etc/sudoers.d/agent-monitor
visudo -cf /etc/sudoers.d/agent-monitor

# Preserve any other cron jobs; do not add duplicates when re-run.
entry="* * * * * $AGENT_HOME/bin/monitor.sh >> $LOG_DIR/cron.log 2>&1"
current=$(crontab -u agent-admin -l 2>/dev/null || true)
if ! grep -Fqx "$entry" <<< "$current"; then
    { [[ -z "$current" ]] || printf '%s\n' "$current"; printf '%s\n' "$entry"; } | crontab -u agent-admin -
fi
printf 'Provisioned accounts, ACLs, environment, scripts and agent-admin cron.\n'
printf 'Use scripts/secure-network.sh --apply at the VM console for SSH/UFW.\n'
printf 'Install the supplied application separately before running it.\n'
