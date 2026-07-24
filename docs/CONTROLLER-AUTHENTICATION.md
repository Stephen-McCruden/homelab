# Controller Authentication

This repository supports two Ansible SSH workflows:

1. A FIDO2 SSH key stored on a YubiKey or compatible security key.
2. A normal OpenSSH private key stored as a file on the controller.

The GitHub fine-grained token and SOPS age key are separate from Ansible SSH authentication.

## Authentication Layers

```text
Terraform -> Proxmox API token
Ansible   -> SSH private key or YubiKey-backed SSH key
Flux      -> GitHub fine-grained token during first bootstrap
Flux sync -> Generated GitHub SSH deploy key after bootstrap
SOPS      -> age private key on the Ansible controller
kubectl   -> Administrative kubeconfig
```

Do not combine these into one credential or store them in the repository.

## YubiKey-Backed Ansible SSH

The wrapper is:

```text
scripts/ansible-yubikey
```

It performs the following actions for the Ansible process:

- Clears `SSH_AUTH_SOCK` so the SSH agent is not used.
- Sets `SSH_ASKPASS` and forces askpass behavior.
- Uses `IdentitiesOnly=yes`.
- Uses the FIDO2 key at `~/.ssh/id_ed25519_sk` by default.
- Runs with one Ansible fork to keep PIN and touch prompts predictable.

From the `ansible/` directory:

```bash
../scripts/ansible-yubikey playbooks/system-init.yml
../scripts/ansible-yubikey playbooks/cluster-bootstrap.yml
../scripts/ansible-yubikey playbooks/platform-bootstrap.yml
```

Override the key path when needed:

```bash
export ANSIBLE_YUBIKEY_PATH="$HOME/.ssh/id_ed25519_sk_homelab"
../scripts/ansible-yubikey playbooks/system-init.yml
unset ANSIBLE_YUBIKEY_PATH
```

Verify the public key exists:

```bash
test -f "$HOME/.ssh/id_ed25519_sk.pub"
```

Test direct access:

```bash
ssh -o IdentitiesOnly=yes \
  -i "$HOME/.ssh/id_ed25519_sk" \
  stoof@192.168.0.52 true
```

A physical touch is expected when the key was created with user-presence requirements. A PIN may also be required.

## Ansible Without a YubiKey

Use a normal private key such as:

```text
~/.ssh/id_ed25519
```

Protect it:

```bash
chmod 600 "$HOME/.ssh/id_ed25519"
```

Test it:

```bash
ssh -o IdentitiesOnly=yes \
  -i "$HOME/.ssh/id_ed25519" \
  stoof@192.168.0.52 true
```

Set the key path in `ansible/inventory/group_vars/all.yml` or the appropriate inventory variable. Then run Ansible directly:

```bash
ansible-playbook playbooks/system-init.yml
ansible-playbook playbooks/cluster-bootstrap.yml
ansible-playbook playbooks/platform-bootstrap.yml
```

An SSH agent may be used, but the explicit inventory key path is easier to reproduce and troubleshoot.

## GitHub Token With Either SSH Method

The GitHub token is required only when the current cluster has not been bootstrapped by Flux.

Interactive method:

```bash
read -rsp "GitHub fine-grained token: " GITHUB_TOKEN
printf '\n'
export GITHUB_TOKEN
```

Confirm that the variable exists without printing it:

```bash
test -n "${GITHUB_TOKEN:-}" && echo "GITHUB_TOKEN is loaded"
```

Optional GitHub API check:

```bash
curl --fail --silent --show-error \
  -H "Authorization: Bearer ${GITHUB_TOKEN}" \
  -H "X-GitHub-Api-Version: 2022-11-28" \
  https://api.github.com/user \
  >/dev/null
```

Run the platform bootstrap.

With YubiKey-backed SSH:

```bash
../scripts/ansible-yubikey playbooks/platform-bootstrap.yml
```

Without a YubiKey:

```bash
ansible-playbook playbooks/platform-bootstrap.yml
```

Remove the variable afterward:

```bash
unset GITHUB_TOKEN
test -z "${GITHUB_TOKEN:-}" && echo "GITHUB_TOKEN removed from this shell"
```

`unset` removes the token from the current shell environment. It does not revoke or delete the token on GitHub.

For a token created only for bootstrap, revoke it in GitHub after the deployment succeeds or give it a short expiration and allow it to expire.

## Subshell Method

A subshell removes the token automatically when the command group exits:

```bash
(
  read -rsp "GitHub fine-grained token: " GITHUB_TOKEN
  printf '\n'
  export GITHUB_TOKEN

  ansible-playbook playbooks/platform-bootstrap.yml
)
```

YubiKey version:

```bash
(
  read -rsp "GitHub fine-grained token: " GITHUB_TOKEN
  printf '\n'
  export GITHUB_TOKEN

  ../scripts/ansible-yubikey playbooks/platform-bootstrap.yml
)
```

The token is unavailable in the parent shell after the closing parenthesis.

## Password Manager Method

A password manager can supply the token instead of manual entry. The exact command depends on the password manager.

Example using `pass`:

```bash
GITHUB_TOKEN="$(pass show YOUR/PASS/ENTRY | head -n 1)"
export GITHUB_TOKEN

../scripts/ansible-yubikey playbooks/platform-bootstrap.yml

unset GITHUB_TOKEN
```

When `pass` is protected by a GPG key on a YubiKey, retrieving the token may require the YubiKey. The token is still a GitHub credential and must be unset after use.

## SOPS With Either SSH Method

The default age key path is:

```text
~/.config/sops/age/keys.txt
```

Use a different path with:

```bash
export SOPS_AGE_KEY_FILE="/secure/path/keys.txt"
```

The current Flux bootstrap role reads the file from the controller, copies it temporarily to the control-plane node, creates or updates `flux-system/sops-age`, and removes the temporary file.

The SSH key type does not change this behavior.

## Kubeconfig

The local administrative kubeconfig is:

```text
~/.kube/homelab-admin.conf
```

Protect it:

```bash
chmod 600 "$HOME/.kube/homelab-admin.conf"
```

Load it for local commands:

```bash
export KUBECONFIG="$HOME/.kube/homelab-admin.conf"
```

Remove the override when finished:

```bash
unset KUBECONFIG
```
