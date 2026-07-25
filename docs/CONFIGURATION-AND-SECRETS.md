# Configuration and Secrets

The repository is public. It may contain topology, usernames, public keys,
public SOPS recipients, and encrypted SOPS documents. It must not contain
passwords, tokens, private keys, kubeconfigs, unencrypted recovery material, or
secret values copied from Kubernetes.

## Configuration Model

| Configuration | Tracked | Contains secrets |
|---|---:|---:|
| `terraform/terraform.tfvars.example` | Yes | Placeholders only |
| `terraform/terraform.tfvars` | No | Yes |
| `ansible/inventory/hosts.yml` | Yes | No |
| `ansible/inventory/group_vars/all.yml` | Yes | No |
| Ansible `*.example` files | Yes | No |
| `.sops.yaml` | Yes | Public age recipient only |
| `azure-credentials.sops.yaml` | Yes | Encrypted values |
| `ansible/platform-bootstrap.env.example` | Yes | Placeholders only |
| SOPS age identity | No | Yes |
| Administrative kubeconfig | No | Yes |

The reference inventory is intentionally tracked because it documents the
reproducible topology. A reproducer may either replace it in a fork or maintain
environment overlays, but should not pretend that the current `.yml` files are
ignored.

## Credential Inventory

| Credential | Normal location | Consumer | Recovery requirement |
|---|---|---|---|
| Proxmox API token | local `terraform.tfvars` | Terraform | Password manager or secure backup |
| Proxmox root SSH access | local SSH configuration | Terraform provider | Proxmox recovery process |
| Node SSH key | YubiKey or controller file | Ansible | Spare key and authorized public key |
| GitHub bootstrap PAT | temporary shell environment | Flux bootstrap | Recreate when needed |
| Flux deploy key | `flux-system/flux-system` Secret | Flux | Recreated by bootstrap |
| SOPS age identity | `~/.config/sops/age/keys.txt` | Ansible and SOPS | Two tested offline copies |
| Azure service principal | SOPS-encrypted manifest | External Secrets | Azure identity recovery |
| Runtime application secrets | Azure Key Vault | External Secrets | Azure backup/recovery |
| Kubernetes admin kubeconfig | `~/.kube/homelab-admin.conf` | Operator | Recreated by Ansible |

## Terraform Variables

Create the local file:

```bash
cd terraform
cp -n terraform.tfvars.example terraform.tfvars
chmod 600 terraform.tfvars
git check-ignore -v terraform.tfvars
```

Replace every placeholder. Never place a private SSH key in this file; only
complete public OpenSSH key lines belong in `ssh_public_keys`.

Review configuration without printing sensitive values:

```bash
terraform fmt -recursive
terraform validate
terraform plan
```

Avoid `terraform output -json` or state inspection in shared terminal output.
Terraform state can contain sensitive input values even when the CLI redacts
them.

## Ansible Inventory

The tracked reference files are:

```text
ansible/inventory/hosts.yml
ansible/inventory/group_vars/all.yml
```

They contain:

- node names and addresses
- controller username and local private-key path
- cluster and management CIDRs
- Kubernetes and Cilium versions
- kubeadm endpoint and network values
- kubeconfig destination

They must not contain a private key or password. Validate the effective
inventory:

```bash
cd ansible
ansible-inventory --graph
ansible-inventory --host k8s-master-01
```

The example files show which values a reproducer must adapt.

## GitHub Bootstrap Token

Create a fine-grained PAT with:

```text
Repository access: homelab only
Administration:    Read and write
Contents:          Read and write
Metadata:          Read-only
Expiration:        Short
```

Use a subshell so it does not remain in the parent shell:

```bash
(
  read -rsp "GitHub fine-grained token: " GITHUB_TOKEN
  printf '\n'
  export GITHUB_TOKEN

  ../scripts/ansible-yubikey playbooks/platform-bootstrap.yml
)
```

For a file-backed SSH key:

```bash
(
  read -rsp "GitHub fine-grained token: " GITHUB_TOKEN
  printf '\n'
  export GITHUB_TOKEN

  ansible-playbook playbooks/platform-bootstrap.yml
)
```

Never print the variable. Revoke the token after a successful bootstrap or let
its short expiration end.

## SOPS Age Identity

Default:

```text
~/.config/sops/age/keys.txt
```

Optional override:

```bash
export SOPS_AGE_KEY_FILE="/secure/path/keys.txt"
```

Safe validation:

```bash
SOPS_KEY_PATH="${SOPS_AGE_KEY_FILE:-$HOME/.config/sops/age/keys.txt}"
test -s "$SOPS_KEY_PATH"
grep -q '^AGE-SECRET-KEY-' "$SOPS_KEY_PATH"

sops --decrypt \
  kubernetes/infrastructure/configs/external-secrets/azure-credentials.sops.yaml \
  >/dev/null
```

`.sops.yaml` contains the public recipient and is safe to commit. The identity
line beginning with `AGE-SECRET-KEY-` is private.

## Flux SOPS Bootstrap

`platform-bootstrap.yml` performs:

```text
validate controller age identity
  -> create flux-system namespace
  -> copy identity temporarily to control plane
  -> create or update flux-system/sops-age
  -> remove temporary file
  -> verify age.agekey exists
  -> bootstrap or verify Flux
```

Do not manually create `sops-age` during a normal rebuild.

Verify only metadata:

```bash
kubectl get secret sops-age --namespace flux-system
kubectl get secret sops-age --namespace flux-system \
  --output jsonpath='{.data}' |
  jq 'keys'
```

Expected key:

```text
age.agekey
```

Do not decode or print it.

## Azure Key Vault and External Secrets

The encrypted Azure bootstrap identity allows the `ClusterSecretStore` to read:

```text
cloudflare-api-token
grafana-admin-user
grafana-admin-password
letsencrypt-production-account-key
```

Expected generated Secrets:

| Kubernetes Secret | Namespace | Owner |
|---|---|---|
| `azure-keyvault-bootstrap` | `external-secrets` | Flux/SOPS |
| `cloudflare-api-token` | `cert-manager` | External Secrets |
| `grafana-admin-credentials` | `monitoring` | External Secrets |
| `letsencrypt-production-account-key-managed` | `cert-manager` | External Secrets |

Verify readiness without returning values:

```bash
kubectl get clustersecretstore azure-key-vault
kubectl get externalsecret --all-namespaces
kubectl get secret \
  cloudflare-api-token \
  --namespace cert-manager \
  --output custom-columns='NAME:.metadata.name,TYPE:.type,KEYS:.data' |
  sed 's/map\\[.*\\]/present/'
```

Prefer `kubectl describe externalsecret` when troubleshooting. Do not use
`.data`, base64 decoding, or `stringData` output in a shared transcript.

## Persistent ACME Account

The production ClusterIssuer sets:

```yaml
disableAccountKeyGeneration: true
```

External Secrets must restore
`letsencrypt-production-account-key-managed` before the issuer becomes Ready.
This prevents repeated cluster rebuilds from registering a new production ACME
account.

Treat the account key as private. Base64-encoded Kubernetes Secret data is not
encryption.

## Administrative Kubeconfig

Expected controller path:

```text
~/.kube/homelab-admin.conf
```

Protect and load it:

```bash
chmod 600 "$HOME/.kube/homelab-admin.conf"
export KUBECONFIG="$HOME/.kube/homelab-admin.conf"
```

The file contains cluster-admin credentials. Never commit or upload it.

## Secret Rotation

Use this order:

1. Create the new value at the external authority.
2. Update Azure Key Vault or the local credential store.
3. Force or wait for External Secrets reconciliation.
4. Verify the consumer is healthy.
5. Revoke the old value.
6. Record the date and recovery impact without recording the value.

For the SOPS age identity, add a new recipient and re-encrypt all SOPS files
before removing the old identity. Confirm the new identity can decrypt first.

For the ACME account key, follow cert-manager's account-key rollover process.
Do not simply delete the managed Secret during a rebuild.

## Pre-Commit Secret Review

```bash
git status --short
git diff --cached --check
git diff --cached

git ls-files |
  rg '(^|/)(terraform\\.tfvars|.*admin\\.conf|keys\\.txt)$' &&
  printf 'Review potentially sensitive tracked paths\n'

git diff --cached |
  rg -ni 'password|secret|token|private.?key|api.?key'
```

Every heuristic match must be reviewed. Variable names, SOPS ciphertext, and
public recipients can match legitimately.

If a credential is committed, treat it as compromised even if the commit is
later removed. Revoke or rotate it first, then clean history if required.
