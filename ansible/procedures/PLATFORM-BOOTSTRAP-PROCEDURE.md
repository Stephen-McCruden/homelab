# Flux Platform Bootstrap Procedure

## Purpose

Provision the Flux SOPS bootstrap Secret, connect the cluster to GitHub, and
wait for the complete GitOps dependency graph.

## Preconditions

- `cluster-bootstrap.yml` completed.
- Kubernetes API reports `ok` at `/readyz`.
- `/etc/kubernetes/admin.conf` exists on `k8s-master-01`.
- the desired repository commit is pushed to `main`.
- Flux owner, repository, branch, and cluster path are correct.
- the controller SOPS age identity can decrypt the Azure bootstrap manifest.
- Azure Key Vault contains all documented runtime secrets.
- a short-lived GitHub token is available if Flux is absent.

## Preflight

```bash
cd /path/to/homelab/ansible

ansible-playbook playbooks/platform-bootstrap.yml --syntax-check
ansible-lint --profile min playbooks/platform-bootstrap.yml
```

Validate the SOPS identity:

```bash
SOPS_KEY_PATH="${SOPS_AGE_KEY_FILE:-$HOME/.config/sops/age/keys.txt}"
test -s "$SOPS_KEY_PATH"
grep -q '^AGE-SECRET-KEY-' "$SOPS_KEY_PATH"

cd ..
sops --decrypt \
  kubernetes/infrastructure/configs/external-secrets/azure-credentials.sops.yaml \
  >/dev/null
cd ansible
```

## First Bootstrap Token

Create a short-lived fine-grained PAT for only the homelab repository:

```text
Administration: Read and write
Contents:       Read and write
Metadata:       Read-only
```

Flux uses it to create a read-only SSH deploy key. Later healthy runs do not
need the PAT.

## Execute a New Bootstrap

YubiKey:

```bash
(
  read -rsp "GitHub fine-grained token: " GITHUB_TOKEN
  printf '\n'
  export GITHUB_TOKEN

  ../scripts/ansible-yubikey playbooks/platform-bootstrap.yml
)
```

File-backed key:

```bash
(
  read -rsp "GitHub fine-grained token: " GITHUB_TOKEN
  printf '\n'
  export GITHUB_TOKEN

  ansible-playbook playbooks/platform-bootstrap.yml
)
```

## Expected Sequence

```text
validate Kubernetes API
  -> install/checksum-verify Flux CLI v2.9.1
  -> validate controller SOPS age identity
  -> create flux-system namespace
  -> create/update flux-system/sops-age
  -> detect complete or absent Flux bootstrap state
  -> bootstrap GitHub only when absent
  -> verify SSH deploy-key Secret
  -> wait for Flux controllers and Git source
  -> wait for the six core Kustomizations configured in the role
  -> run flux check
```

Flux continues reconciling the Tailscale Operator, Tailscale ingress
configuration, and website image automation after those core checks. Validate
the complete graph during acceptance.

## Pull the Generated Commit

On a first bootstrap, Flux writes its generated manifests:

```bash
cd /path/to/homelab
git pull --rebase origin main
```

Review the generated files under `clusters/homelab/flux-system/`.

## Acceptance

```bash
export KUBECONFIG="$HOME/.kube/homelab-admin.conf"

flux check
flux get sources git --all-namespaces
kubectl get kustomizations --namespace flux-system
kubectl get helmreleases --all-namespaces
```

Expected Kustomizations:

```text
flux-system
infrastructure-controllers
infrastructure-configs
applications
infrastructure-kubelet-csr-approver
infrastructure-metrics-server
infrastructure-tailscale-operator
infrastructure-tailscale-ingress
<WEBSITE_IMAGE_AUTOMATION_KUSTOMIZATION>
```

Every Ready condition must be `True`.

Verify bootstrap and runtime dependencies without returning values:

```bash
kubectl get secret sops-age --namespace flux-system
kubectl get clustersecretstore
kubectl get externalsecret --all-namespaces
kubectl get clusterissuer
kubectl get certificate --all-namespaces
kubectl get certificatesigningrequests
kubectl top nodes
```

## Later Runs

```bash
../scripts/ansible-yubikey playbooks/platform-bootstrap.yml
```

No `GITHUB_TOKEN` is required while Flux's GitRepository, root Kustomization,
and authentication Secret all exist. The playbook still verifies the controller
SOPS identity and reconciles `sops-age`.

## Troubleshooting

### Token required

Flux is absent. Load a valid fine-grained PAT and rerun.

### GitHub permission

Check owner, repository scope, expiration, Administration read/write, Contents
read/write, and Metadata read-only.

### SOPS identity

Check the default path or `SOPS_AGE_KEY_FILE`. Never place the identity in Git.

### Partial Flux state

The role fails unless GitRepository, root Kustomization, and authentication
Secret are all present or all absent:

```bash
kubectl get gitrepository,kustomization,secret --namespace flux-system
```

Inspect before deleting anything.

### Kustomization dependency

```bash
kubectl get kustomizations --namespace flux-system
kubectl describe kustomization NAME --namespace flux-system
kubectl get helmreleases --all-namespaces
kubectl get events --all-namespaces --sort-by=.lastTimestamp
```

Fix the first stalled resource.

### Source revision is old

```bash
flux reconcile source git flux-system \
  --namespace flux-system \
  --timeout=5m

flux reconcile kustomization NAME \
  --namespace flux-system \
  --with-source \
  --timeout=10m
```

See [Troubleshooting](../../docs/TROUBLESHOOTING.md) for the complete failure
tree.
