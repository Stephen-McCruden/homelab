# Configuration and Secrets

This repository is public. Real credentials, private keys, recovery material, kubeconfigs, and unencrypted secret values must not be committed.

## Tracked Examples

The following files can be committed because they contain placeholders or documentation only:

```text
terraform/terraform.tfvars.example
ansible/inventory/hosts.yml.example
ansible/inventory/group_vars/all.yml.example
ansible/platform-bootstrap.env.example
```

## Local Files

The following files normally contain environment-specific values and should remain outside Git:

```text
terraform/terraform.tfvars
ansible/inventory/hosts.yml
ansible/inventory/group_vars/all.yml
ansible/platform-bootstrap.env
```

The following sensitive files are stored outside the repository:

```text
~/.ssh/id_ed25519
~/.ssh/id_ed25519_sk
~/.config/sops/age/keys.txt
~/.kube/homelab-admin.conf
```

## Required Git Ignore Entries

Confirm the repository ignores local secret-bearing files. At minimum:

```gitignore
terraform/terraform.tfvars
ansible/inventory/hosts.yml
ansible/inventory/group_vars/all.yml
ansible/platform-bootstrap.env
```

Verify each local file:

```bash
git check-ignore -v terraform/terraform.tfvars
git check-ignore -v ansible/inventory/hosts.yml
git check-ignore -v ansible/inventory/group_vars/all.yml
```

If a local `ansible/platform-bootstrap.env` file is used:

```bash
git check-ignore -v ansible/platform-bootstrap.env
```

## Should a Real Environment File Be Created?

A tracked example file is useful. A persistent plaintext file containing the GitHub token is not recommended.

Recommended approach:

- Keep `ansible/platform-bootstrap.env.example` in Git.
- Load `GITHUB_TOKEN` interactively or from a password manager.
- Use `SOPS_AGE_KEY_FILE` only when the age key is not at the default path.
- Unset temporary environment variables after the command.

A local `ansible/platform-bootstrap.env` can be used if required, but it must be ignored, mode `0600`, and treated as a secret file. Do not leave a long-lived GitHub token in it.

## Platform Bootstrap Environment Variables

| Variable | Required | Purpose |
|---|---:|---|
| `GITHUB_TOKEN` | First Flux bootstrap only | Allows Flux to commit bootstrap manifests and create the GitHub deploy key. |
| `SOPS_AGE_KEY_FILE` | Optional | Overrides the default SOPS age key path. |
| `ANSIBLE_YUBIKEY_PATH` | Optional | Overrides the YubiKey-backed SSH key path used by the wrapper. |
| `SSH_ASKPASS` | Optional | Overrides the askpass executable used by the YubiKey wrapper. |
| `KUBECONFIG` | Optional for local commands | Selects the local administrative kubeconfig. |

The Ansible role reads `GITHUB_TOKEN` and `SOPS_AGE_KEY_FILE` from the controller environment.

## GitHub Fine-Grained Token

The current bootstrap uses:

```text
--token-auth=false
--read-write-key=false
```

Create a fine-grained personal access token with:

```text
Resource owner:     the account that owns the repository
Repository access:  only the homelab repository
Administration:     Read and write
Contents:           Read and write
Metadata:           Read-only
```

Use a short expiration.

### Load interactively

```bash
read -rsp "GitHub fine-grained token: " GITHUB_TOKEN
printf '\n'
export GITHUB_TOKEN
```

Confirm it is set without printing it:

```bash
test -n "${GITHUB_TOKEN:-}" && echo "GITHUB_TOKEN is loaded"
```

Optional API validation:

```bash
curl --fail --silent --show-error \
  -H "Authorization: Bearer ${GITHUB_TOKEN}" \
  -H "X-GitHub-Api-Version: 2022-11-28" \
  https://api.github.com/user \
  >/dev/null
```

### Remove it

```bash
unset GITHUB_TOKEN
test -z "${GITHUB_TOKEN:-}" && echo "GITHUB_TOKEN removed from this shell"
```

This removes the variable from the current shell only. Revoke the token separately in GitHub when it is no longer needed.

### Safer one-command scope

Use a subshell so the token cannot remain in the parent shell:

```bash
(
  read -rsp "GitHub fine-grained token: " GITHUB_TOKEN
  printf '\n'
  export GITHUB_TOKEN

  ansible-playbook playbooks/platform-bootstrap.yml
)
```

YubiKey SSH version:

```bash
(
  read -rsp "GitHub fine-grained token: " GITHUB_TOKEN
  printf '\n'
  export GITHUB_TOKEN

  ../scripts/ansible-yubikey playbooks/platform-bootstrap.yml
)
```

## SOPS Age Private Key

Default path:

```text
~/.config/sops/age/keys.txt
```

Optional override:

```bash
export SOPS_AGE_KEY_FILE="/secure/path/keys.txt"
```

Validate without displaying the private key:

```bash
SOPS_KEY_PATH="${SOPS_AGE_KEY_FILE:-$HOME/.config/sops/age/keys.txt}"

test -s "$SOPS_KEY_PATH" \
  && echo "SOPS age key file found"

grep -q '^AGE-SECRET-KEY-' "$SOPS_KEY_PATH" \
  && echo "SOPS age identity found"
```

Remove an override when finished:

```bash
unset SOPS_AGE_KEY_FILE
```

The key file itself is not deleted by `unset`.

## Automated SOPS Secret Creation

During `platform-bootstrap.yml`, Ansible now performs this sequence:

```text
Verify the age private key exists on the controller
    -> create flux-system namespace if needed
    -> copy the key temporarily to the control-plane node
    -> create or update flux-system/sops-age
    -> remove the temporary control-plane file
    -> verify the Secret contains age.agekey
    -> continue with Flux bootstrap and reconciliation
```

Do not manually create `sops-age` during a normal rebuild.

Verify only the Secret and key name:

```bash
kubectl get secret sops-age -n flux-system

kubectl get secret sops-age -n flux-system \
  -o jsonpath='{.data}' |
  jq 'keys'
```

Expected key:

```text
age.agekey
```

Do not print or decode the Secret value.

## SOPS-Encrypted Repository Files

The encrypted Azure credential manifest is expected to remain encrypted in Git.

Test local decryption without writing plaintext to disk:

```bash
sops --decrypt \
  kubernetes/infrastructure/configs/external-secrets/azure-credentials.sops.yaml \
  >/dev/null
```

A successful command confirms that the local age key can decrypt the file.

## Terraform Variables

Create the local variable file:

```bash
cp terraform/terraform.tfvars.example terraform/terraform.tfvars
chmod 600 terraform/terraform.tfvars
git check-ignore -v terraform/terraform.tfvars
```

The file can contain the Proxmox API token secret, infrastructure values, public SSH keys, addresses, and resource sizing.

Never place a private SSH key in Terraform variables.

## Ansible Inventory

Create local inventory files:

```bash
cp ansible/inventory/hosts.yml.example \
  ansible/inventory/hosts.yml

cp ansible/inventory/group_vars/all.yml.example \
  ansible/inventory/group_vars/all.yml
```

The inventory may reference a local private-key path. The private key remains outside the repository.

## Kubernetes Kubeconfig

Local path:

```text
~/.kube/homelab-admin.conf
```

Protect it:

```bash
chmod 600 "$HOME/.kube/homelab-admin.conf"
```

Do not commit it.

## Azure Key Vault and External Secrets

SOPS protects the Azure bootstrap credential manifest stored in Git. External Secrets Operator then uses Azure Key Vault for runtime secrets such as:

- Cloudflare API token.
- Grafana administrative credentials.
- Future application credentials.

The repository should contain only encrypted bootstrap credentials and non-secret references to Key Vault secret names.

## Pre-Commit Review

```bash
git status --short
git diff --cached --check
git diff --cached
```

Verify ignored files:

```bash
git check-ignore -v terraform/terraform.tfvars
git check-ignore -v ansible/inventory/hosts.yml
git check-ignore -v ansible/inventory/group_vars/all.yml
```

Optional heuristic:

```bash
git diff --cached | grep -Ei \
  'password|secret|token|private.?key|api.?key'
```

Review every match. Encrypted SOPS fields and variable names can match this search legitimately.

## Official References

- [Flux bootstrap for GitHub](https://fluxcd.io/flux/installation/bootstrap/github/)
- [GitHub personal access token management](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/managing-your-personal-access-tokens)
