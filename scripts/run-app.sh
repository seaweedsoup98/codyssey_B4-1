#!/usr/bin/env bash
# Run the official provided application as agent-admin (never as root).
set -euo pipefail
[[ "$(id -un)" == agent-admin && "$EUID" -ne 0 ]] || {
    echo '[FAIL] Run this script as agent-admin.' >&2
    exit 1
}
. /home/agent-admin/agent-app/agent-app.env

case "$(uname -m)" in
    x86_64|amd64) app="$AGENT_HOME/agent-app-linux-x86" ;;
    aarch64|arm64) app="$AGENT_HOME/agent-app-linux-arm64" ;;
    *) echo '[FAIL] Unsupported CPU architecture.' >&2; exit 1 ;;
esac

if [[ -x "$app" ]]; then
    exec "$app"
elif [[ -f "$AGENT_HOME/agent_app.py" ]]; then
    exec python3 "$AGENT_HOME/agent_app.py"
else
    echo "[FAIL] Install the official supplied app at $app (or agent_app.py)." >&2
    exit 1
fi
