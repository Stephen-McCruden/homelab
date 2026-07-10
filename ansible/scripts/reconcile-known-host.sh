#!/usr/bin/env bash
# FILE PATH: scripts/reconcile-known-host.sh
set -euo pipefail
host="${1:?host required}"; known_hosts="${2:?known_hosts path required}"
mkdir -p "$(dirname "$known_hosts")"; touch "$known_hosts"; chmod 600 "$known_hosts"
scan="$(mktemp)"; trap 'rm -f "$scan"' EXIT
for i in {1..12}; do ssh-keyscan -T 5 -H "$host" >"$scan" 2>/dev/null && [[ -s "$scan" ]] && break; sleep 5; done
[[ -s "$scan" ]] || { echo "Unable to scan SSH host key for $host" >&2; exit 1; }
old="$(ssh-keygen -F "$host" -f "$known_hosts" 2>/dev/null || true)"
if [[ -n "$old" ]]; then
  current_plain="$(ssh-keyscan -T 5 "$host" 2>/dev/null | awk '{print $2" "$3}' | sort -u)"
  old_plain="$(printf '%s
' "$old" | awk '!/^#/ {print $2" "$3}' | sort -u)"
  [[ "$current_plain" == "$old_plain" ]] && { echo "UNCHANGED: $host"; exit 0; }
  ssh-keygen -R "$host" -f "$known_hosts" >/dev/null
fi
cat "$scan" >> "$known_hosts"; echo "UPDATED: $host"
