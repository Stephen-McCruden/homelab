#!/usr/bin/env bash
# FILE PATH: scripts/reconcile-known-host.sh
# PURPOSE: Reconcile Terraform-recreated host keys without reporting false changes.
set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "Usage: $0 <host> <known_hosts_file>" >&2
  exit 2
fi

host="$1"
known_hosts="$2"
known_hosts_dir="$(dirname "$known_hosts")"

mkdir -p "$known_hosts_dir"
chmod 0700 "$known_hosts_dir"
touch "$known_hosts"
chmod 0600 "$known_hosts"

scan_file="$(mktemp)"
scan_keys="$(mktemp)"
existing_keys="$(mktemp)"
cleanup() {
  rm -f "$scan_file" "$scan_keys" "$existing_keys"
}
trap cleanup EXIT

# Obtain all currently offered host keys. Sorting removes ordering differences
# between ssh-keyscan runs.
ssh-keyscan -T 10 "$host" 2>/dev/null | sort -u > "$scan_file"

if [[ ! -s "$scan_file" ]]; then
  echo "ERROR: no SSH host key returned for $host" >&2
  exit 1
fi

# Compare only key algorithm and key material. The hostname field may be plain,
# bracketed, comma-separated, or hashed without representing a key change.
awk 'NF >= 3 {print $2, $3}' "$scan_file" | sort -u > "$scan_keys"

ssh-keygen -F "$host" -f "$known_hosts" 2>/dev/null \
  | awk '!/^#/ && NF >= 3 {print $2, $3}' \
  | sort -u > "$existing_keys" || true

if [[ -s "$existing_keys" ]] && cmp -s "$existing_keys" "$scan_keys"; then
  echo "UNCHANGED: $host"
  exit 0
fi

# Remove every old entry for this address before writing the freshly scanned set.
ssh-keygen -R "$host" -f "$known_hosts" >/dev/null 2>&1 || true
cat "$scan_file" >> "$known_hosts"

echo "UPDATED: $host"
