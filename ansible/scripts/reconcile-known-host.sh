#!/usr/bin/env bash
# FILE PATH: scripts/reconcile-known-host.sh
set -euo pipefail
host=${1:?host required}
known_hosts=${2:?known_hosts path required}
mkdir -p "$(dirname "$known_hosts")"
touch "$known_hosts"
scan=$(mktemp)
existing=$(mktemp)
trap 'rm -f "$scan" "$existing"' EXIT
ssh-keyscan -T 10 "$host" 2>/dev/null | awk '!/^#/ {print $2, $3}' | sort -u > "$scan"
if [[ ! -s "$scan" ]]; then
  echo "ERROR: no SSH host keys returned for $host" >&2
  exit 1
fi
ssh-keygen -F "$host" -f "$known_hosts" 2>/dev/null | awk '!/^#/ && NF >= 3 {print $2, $3}' | sort -u > "$existing" || true
if cmp -s "$scan" "$existing"; then
  echo "UNCHANGED: $host"
  exit 0
fi
ssh-keygen -R "$host" -f "$known_hosts" >/dev/null 2>&1 || true
ssh-keyscan -T 10 "$host" 2>/dev/null >> "$known_hosts"
chmod 600 "$known_hosts"
echo "UPDATED: $host"
