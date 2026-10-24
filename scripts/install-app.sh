#!/usr/bin/env bash
# Install the official application archive on an already provisioned Linux VM.
set -euo pipefail

if [[ $EUID -ne 0 || $# -ne 1 || ! -f $1 ]]; then
    printf 'Usage: sudo bash scripts/install-app.sh /path/to/agent-app.zip\n' >&2
    exit 1
fi

case "$(uname -m)" in
    x86_64|amd64) binary=agent-app-linux-x86 ;;
    aarch64|arm64) binary=agent-app-linux-arm64 ;;
    *) printf '[FAIL] Unsupported CPU architecture.\n' >&2; exit 1 ;;
esac

home=/home/agent-admin/agent-app
destination="$home/$binary"
[[ -d $home && ! -L $destination ]] || {
    printf '[FAIL] Run provision.sh first; the app destination must not be a symlink.\n' >&2
    exit 1
}

workdir=$(mktemp -d)
trap 'rm -rf -- "$workdir"' EXIT
unzip -p "$1" "$binary" > "$workdir/$binary" || {
    printf '[FAIL] The official ZIP does not contain %s.\n' "$binary" >&2
    exit 1
}
[[ -s $workdir/$binary ]] || { printf '[FAIL] Empty executable.\n' >&2; exit 1; }
if [[ -e $destination ]] && ! cmp -s "$workdir/$binary" "$destination"; then
    printf '[FAIL] A different application is already installed: %s\n' "$destination" >&2
    exit 1
fi
install -o agent-admin -g agent-core -m 750 "$workdir/$binary" "$destination"
printf '[OK] Installed %s as agent-admin:agent-core (750).\n' "$destination"
