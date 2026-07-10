#!/usr/bin/env bash
# FILE PATH: scripts/reconcile-known-host.sh
# PURPOSE: Keep this file at exactly this path inside the Ansible project.
set -euo pipefail

address="${1:?usage: reconcile-known-host.sh ADDRESS [KNOWN_HOSTS_FILE]}"
known_hosts_file="${2:-${HOME}/.ssh/known_hosts}"
ssh_dir="$(dirname "$known_hosts_file")"

mkdir -p "$ssh_dir"
touch "$known_hosts_file"
chmod 700 "$ssh_dir"
chmod 600 "$known_hosts_file"

scan_output="$(ssh-keyscan -T 10 -t ed25519 "$address" 2>/dev/null || true)"
if [[ -z "$scan_output" ]]; then
  echo "ERROR: unable to retrieve an ED25519 SSH host key from ${address}" >&2
  exit 2
fi

current_keys="$(ssh-keygen -F "$address" -f "$known_hosts_file" 2>/dev/null \
  | awk '!/^#/ && NF >= 3 {print $2 " " $3}' \
  | sort -u || true)"
scanned_keys="$(printf '%s\n' "$scan_output" \
  | awk 'NF >= 3 {print $2 " " $3}' \
  | sort -u)"

if [[ "$current_keys" == "$scanned_keys" ]]; then
  echo "UNCHANGED: ${address}"
  exit 0
fi

ssh-keygen -R "$address" -f "$known_hosts_file" >/dev/null 2>&1 || true
printf '%s\n' "$scan_output" >> "$known_hosts_file"
chmod 600 "$known_hosts_file"
echo "UPDATED: ${address}"
