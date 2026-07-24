# Flux Platform Bootstrap Procedure

## Purpose

Install Flux, create the SOPS age Secret, connect Kubernetes to GitHub, and validate the complete GitOps reconciliation chain.

## Current Bootstrap Order

```text
Validate Kubernetes API
    -> install or verify Flux CLI
    -> verify controller-side SOPS age private key
    -> create flux-system namespace
    -> create or update flux-system/sops-age
    -> detect whether Flux bootstrap is required
    -> bootstrap GitHub only when required
    -> validate Flux SSH authentication Secret
    -> wait for controllers and Git source
    -> wait for every managed Kustomization
```

The operator should not manually create `sops-age` during a normal deployment.

## Preconditions

- `cluster-bootstrap.yml` completed successfully.
- Kubernetes API is Ready.
- `/etc/kubernetes/admin.conf` exists on `k8s-master-01`.
- Flux owner, repository, branch, and path variables are correct.
- The GitOps repository content is pushed.
- The controller has the correct SOPS age private key.
- A GitHub fine-grained token is available for a new cluster bootstrap.

## Validate the Playbook

```bash
cd /home/stoof/GitHub/homelab/ansible
ansible-playbook playbooks/platform-bootstrap.yml --syntax-check
ansible-lint playbooks/platform-bootstrap.yml
```

## Verify the SOPS Age Key

Default path:

```text
~/.config/sops/age/keys.txt
```

Optional override:

```bash
export SOPS_AGE_KEY_FILE="/secure/path/keys.txt"
```

Validate without printing it:

```bash
SOPS_KEY_PATH="${SOPS_AGE_KEY_FILE:-$HOME/.config/sops/age/keys.txt}"

test -s "$SOPS_KEY_PATH" \
  && echo "SOPS age key file found"

grep -q '^AGE-SECRET-KEY-' "$SOPS_KEY_PATH" \
  && echo "SOPS age identity found"
```

Optional local decryption test:

```bash
cd /home/stoof/GitHub/homelab
sops --decrypt \
  kubernetes/infrastructure/configs/external-secrets/azure-credentials.sops.yaml \
  >/dev/null
cd ansible
```

## Create the GitHub Fine-Grained Token

For the current SSH deploy-key bootstrap, configure:

```text
Resource owner:     Stephen-McCruden
Repository access:  only homelab
Administration:     Read and write
Contents:           Read and write
Metadata:           Read-only
```

Administration must be read/write because the Flux command uses `--token-auth=false` and creates a deploy key.

Use a short expiration.

## Load the Token

```bash
read -rsp "GitHub fine-grained token: " GITHUB_TOKEN
printf '\n'
export GITHUB_TOKEN
```

Confirm without printing it:

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

## Execute Without a YubiKey

```bash
ansible-playbook playbooks/platform-bootstrap.yml
```

## Execute With YubiKey-Backed SSH

```bash
../scripts/ansible-yubikey playbooks/platform-bootstrap.yml
```

The YubiKey is used for SSH to the Kubernetes node. It does not replace the GitHub token or the SOPS age key.

## Remove the Token

```bash
unset GITHUB_TOKEN
test -z "${GITHUB_TOKEN:-}" && echo "GITHUB_TOKEN removed from this shell"
```

If `SOPS_AGE_KEY_FILE` was exported only for this run:

```bash
unset SOPS_AGE_KEY_FILE
```

`unset` does not revoke the GitHub token. Revoke it in GitHub after successful bootstrap or allow a short-lived token to expire.

## Pull the Flux Commit

On first bootstrap, Flux commits generated manifests to GitHub.

```bash
cd /home/stoof/GitHub/homelab
git pull --rebase origin main
```

## Validate SOPS Secret Creation

```bash
export KUBECONFIG="$HOME/.kube/homelab-admin.conf"

kubectl get secret sops-age -n flux-system
```

Check only the key name:

```bash
kubectl get secret sops-age -n flux-system \
  -o jsonpath='{.data}' |
  jq 'keys'
```

Expected:

```text
age.agekey
```

Do not decode or print the key value.

## Validate Flux

```bash
flux check
flux get sources git -A
kubectl get kustomizations.kustomize.toolkit.fluxcd.io -A
kubectl get helmreleases.helm.toolkit.fluxcd.io -A
```

Expected Kustomizations:

```text
flux-system                 Ready=True
infrastructure-controllers  Ready=True
infrastructure-configs      Ready=True
applications                Ready=True
```

## Validate External Secrets and TLS

```bash
kubectl get clustersecretstore
kubectl get externalsecret -A
kubectl get clusterissuer
kubectl get certificate -A
```

## Validate Traefik Static Ports

```bash
kubectl get service traefik -n traefik -o yaml
```

Expected:

```text
web NodePort:       32492
websecure NodePort: 30860
LoadBalancer IP:    192.168.0.220
```

## Later Runs

A healthy existing Flux installation does not require `GITHUB_TOKEN`.

Without a YubiKey:

```bash
ansible-playbook playbooks/platform-bootstrap.yml
```

With YubiKey-backed SSH:

```bash
../scripts/ansible-yubikey playbooks/platform-bootstrap.yml
```

Ansible still verifies the local SOPS age key and ensures the cluster Secret matches it.

## Troubleshooting

### `Initial Flux bootstrap requires GITHUB_TOKEN`

Flux was not detected in the cluster and the controller environment does not contain the token.

Load the token and rerun the playbook.

### GitHub permission error

Verify:

- The token belongs to the repository owner or has authorized access.
- Repository access includes only the correct repository.
- Administration is read/write.
- Contents is read/write.
- Metadata is read-only.
- The token is not expired or revoked.

### SOPS age key not found

Verify the default path or export `SOPS_AGE_KEY_FILE`.

Do not place the private key in Git.

### `secrets "sops-age" not found`

The updated Ansible role should create the Secret before Flux reconciliation. Confirm the deployed role contains the SOPS tasks and rerun `platform-bootstrap.yml`.

### Encrypted manifest cannot be decrypted

Verify:

- The local age key decrypts the file with `sops --decrypt`.
- `.sops.yaml` contains the matching age recipient.
- `infrastructure-configs` references `secretRef.name: sops-age`.
- The Secret contains the `age.agekey` key.

### Partial Flux state

The role intentionally fails if the GitRepository, root Kustomization, and Flux authentication Secret do not either all exist or all not exist.

Inspect the partial state before deleting anything:

```bash
kubectl get gitrepository,kustomization,secret -n flux-system
```

### Kustomization dependency not Ready

Check in order:

```bash
kubectl get kustomizations.kustomize.toolkit.fluxcd.io -A
kubectl get helmreleases.helm.toolkit.fluxcd.io -A
kubectl get events -A --sort-by=.lastTimestamp
```

Fix the first failing dependency instead of manually forcing every later Kustomization.

## Official Reference

- [Flux bootstrap for GitHub](https://fluxcd.io/flux/installation/bootstrap/github/)
