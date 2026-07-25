# Controller Authentication

The deployment uses separate credentials for separate trust boundaries:

| Connection | Credential |
|---|---|
| Terraform to Proxmox API | Proxmox API token |
| Terraform provider to Proxmox host | Proxmox root SSH access |
| Ansible to Fedora VMs | YubiKey-backed or file-backed SSH key |
| First Flux bootstrap to GitHub | Short-lived fine-grained PAT |
| Later Flux reconciliation | Generated read-only SSH deploy key |
| SOPS decryption | age identity on the controller |
| Operator to Kubernetes | Administrative kubeconfig |

Do not collapse these into one credential or store them in the repository.

## YubiKey-Backed Ansible

The repository wrapper is:

```text
scripts/ansible-yubikey
```

It:

- clears `SSH_AUTH_SOCK`
- forces an askpass prompt
- uses `IdentitiesOnly=yes`
- defaults to `~/.ssh/id_ed25519_sk`
- runs one Ansible fork so PIN and touch prompts are predictable

Confirm the key stubs exist:

```bash
test -f "$HOME/.ssh/id_ed25519_sk"
test -f "$HOME/.ssh/id_ed25519_sk.pub"
```

Test each node:

```bash
for address in 192.168.0.50 192.168.0.51 192.168.0.52; do
  ssh -o IdentitiesOnly=yes \
    -i "$HOME/.ssh/id_ed25519_sk" \
    "stoof@${address}" true
done
```

A PIN and physical touch may be required.

Run playbooks from `ansible/`:

```bash
../scripts/ansible-yubikey playbooks/system-init.yml
../scripts/ansible-yubikey playbooks/cluster-bootstrap.yml
../scripts/ansible-yubikey playbooks/platform-bootstrap.yml
```

Override the identity for one shell:

```bash
export ANSIBLE_YUBIKEY_PATH="$HOME/.ssh/id_ed25519_sk_homelab"
../scripts/ansible-yubikey playbooks/system-init.yml
unset ANSIBLE_YUBIKEY_PATH
```

The matching public key must appear in Terraform's `ssh_public_keys`.

## File-Backed SSH Key

Protect the key:

```bash
chmod 600 "$HOME/.ssh/id_ed25519"
```

Set its path in `ansible/inventory/group_vars/all.yml`, then test:

```bash
ssh -o BatchMode=yes \
  -o IdentitiesOnly=yes \
  -i "$HOME/.ssh/id_ed25519" \
  stoof@192.168.0.52 true

cd ansible
ansible all --module-name ping
```

Run:

```bash
ansible-playbook playbooks/system-init.yml
ansible-playbook playbooks/cluster-bootstrap.yml
ansible-playbook playbooks/platform-bootstrap.yml
```

## First Flux Bootstrap

The GitHub token is required only when Flux is absent:

```bash
(
  read -rsp "GitHub fine-grained token: " GITHUB_TOKEN
  printf '\n'
  export GITHUB_TOKEN

  ../scripts/ansible-yubikey playbooks/platform-bootstrap.yml
)
```

The variable disappears when the subshell exits. Revoke the token after
successful bootstrap or use a short expiration.

Do not pass a token on the command line, save it in shell history, or place it
in `platform-bootstrap.env.example`.

## SOPS Identity

The SSH key does not replace the SOPS key. The default age identity is:

```text
~/.config/sops/age/keys.txt
```

Use an alternative:

```bash
export SOPS_AGE_KEY_FILE="/secure/path/keys.txt"
```

`platform-bootstrap.yml` reads it on the controller and transfers it to the
control-plane node only long enough to create or update `flux-system/sops-age`.

## Kubeconfig

Ansible retrieves:

```text
~/.kube/homelab-admin.conf
```

Use it:

```bash
chmod 600 "$HOME/.kube/homelab-admin.conf"
export KUBECONFIG="$HOME/.kube/homelab-admin.conf"
kubectl auth can-i '*' '*' --all-namespaces
```

Expected output is `yes`; that confirms the file is highly privileged and must
be protected accordingly.

## Recovery

Maintain:

- two FIDO2 keys or a tested emergency file-backed SSH key
- offline copies of the SOPS age identity
- recovery access for GitHub, Azure, HCP Terraform, Cloudflare, and Proxmox
- the public SSH key in the Terraform variable backup

Test recovery credentials periodically. A spare key that has never been used is
an assumption, not a recovery control.
