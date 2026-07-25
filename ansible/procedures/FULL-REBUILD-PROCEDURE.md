# Full Rebuild Procedure

## Purpose

Recreate the Terraform-managed VMs, Fedora baseline, Kubernetes cluster, Flux
installation, SOPS bootstrap Secret, platform controllers, configuration, and
applications after deliberate destruction or total VM loss.

This is the canonical rebuild runbook.

## Recovery Boundary

This procedure currently restores:

- VM definitions
- Fedora and node configuration
- Kubernetes and Cilium
- secure kubelet serving certificates
- Flux and the GitOps dependency graph
- External Secrets and runtime Kubernetes Secrets
- ACME account reuse and wildcard TLS
- current stateless applications

It does not currently restore:

- old etcd state
- PVC contents
- databases
- application uploads
- Prometheus history
- Grafana UI changes not declared in Git

Do not destroy important state until
[Storage and backups](../../docs/STORAGE-AND-BACKUPS.md) has a tested restore
for it.

## Proof Record

Before starting, create an operator note containing:

```text
Date:
Operator:
Git commit:
HCP workspace:
Start time:
Reason:
Expected data loss:
```

Record every stage start/end, first failure, diagnostic command, mutation, and
final result. A rebuild is proven only if no undocumented corrective mutation
is required.

## Phase 0: Destructive Preflight

From the repository root:

```bash
cd /path/to/homelab
REPO_ROOT="$(pwd)"

git status --short
git pull --ff-only origin main
git rev-parse HEAD
```

Stop if the working tree contains uncommitted desired state or required changes
have not been pushed.

### Verify Terraform state

```bash
cd "$REPO_ROOT/terraform"
terraform login
terraform init
terraform state list
terraform show
terraform plan -destroy
```

Confirm the HCP organization/workspace and exact destroy targets.

### Verify local configuration

```bash
test -s terraform.tfvars
git check-ignore -v terraform.tfvars

cd "$REPO_ROOT/ansible"
ansible-inventory --graph
test -f inventory/hosts.yml
test -f inventory/group_vars/all.yml
```

### Verify SSH recovery

```bash
test -f "$HOME/.ssh/id_ed25519_sk"
test -f "$HOME/.ssh/id_ed25519_sk.pub"
```

Or verify the selected file-backed key.

### Verify SOPS recovery

```bash
cd "$REPO_ROOT"
SOPS_KEY_PATH="${SOPS_AGE_KEY_FILE:-$HOME/.config/sops/age/keys.txt}"
test -s "$SOPS_KEY_PATH"
grep -q '^AGE-SECRET-KEY-' "$SOPS_KEY_PATH"

sops --decrypt \
  kubernetes/infrastructure/configs/external-secrets/azure-credentials.sops.yaml \
  >/dev/null
```

Confirm a second offline copy exists and has been tested.

### Verify Azure recovery inputs

Expected enabled Key Vault entries:

```text
cloudflare-api-token
grafana-admin-user
grafana-admin-password
letsencrypt-production-account-key
```

List names and enabled state without values:

```bash
az keyvault secret list \
  --vault-name kvhomelab91c977 \
  --query '[].{name:name,enabled:attributes.enabled}' \
  --output table
```

### Verify external network configuration

```text
WAN TCP 80  -> 192.168.0.52:32492
WAN TCP 443 -> 192.168.0.52:30860
```

Confirm public DNS and reserve:

```text
192.168.0.50
192.168.0.51
192.168.0.52
192.168.0.220-192.168.0.229
```

### Verify application backups

For every stateful application, record:

- latest successful backup time
- external target
- most recent restore-test date
- accepted RPO

If any required check fails, stop. Do not destroy.

## Phase 1: Validate the Desired Commit

```bash
cd "$REPO_ROOT/terraform"
terraform fmt -check -recursive
terraform validate

cd "$REPO_ROOT/ansible"
ansible-playbook playbooks/system-init.yml --syntax-check
ansible-playbook playbooks/cluster-bootstrap.yml --syntax-check
ansible-playbook playbooks/platform-bootstrap.yml --syntax-check
ansible-lint --profile min playbooks/system-init.yml
ansible-lint --profile min playbooks/cluster-bootstrap.yml
ansible-lint --profile min playbooks/platform-bootstrap.yml
yamllint .

cd "$REPO_ROOT"
kubectl kustomize kubernetes/infrastructure/controllers/core >/dev/null
kubectl kustomize kubernetes/infrastructure/controllers/kubelet-csr-approver >/dev/null
kubectl kustomize kubernetes/infrastructure/controllers/metrics-server >/dev/null
kubectl kustomize kubernetes/infrastructure/configs >/dev/null
kubectl kustomize kubernetes/applications/homelab >/dev/null
```

## Phase 2: Destroy and Recreate VMs

```bash
cd "$REPO_ROOT/terraform"
terraform destroy
terraform plan -out=tfplan
terraform apply tfplan
rm -f ./tfplan
```

The explicitly named local plan is no longer needed after apply.

Wait for cloud-init, then:

```bash
for address in 192.168.0.50 192.168.0.51 192.168.0.52; do
  ping -c 2 "$address"
done
```

YubiKey SSH:

```bash
for address in 192.168.0.50 192.168.0.51 192.168.0.52; do
  ssh -o IdentitiesOnly=yes \
    -i "$HOME/.ssh/id_ed25519_sk" \
    "stoof@${address}" true
done
```

Do not continue until every node accepts SSH.

## Phase 3: System Initialization

```bash
cd "$REPO_ROOT/ansible"
../scripts/ansible-yubikey playbooks/system-init.yml
```

Or:

```bash
ansible-playbook playbooks/system-init.yml
```

Require `failed=0` and `unreachable=0`.

## Phase 4: Kubernetes Bootstrap

```bash
../scripts/ansible-yubikey playbooks/cluster-bootstrap.yml
```

Or:

```bash
ansible-playbook playbooks/cluster-bootstrap.yml
```

Load access:

```bash
export KUBECONFIG="$HOME/.kube/homelab-admin.conf"
chmod 600 "$KUBECONFIG"
```

Gate:

```bash
kubectl get --raw=/readyz
kubectl get nodes -o wide
kubectl get pods --namespace kube-system -o wide
```

All nodes must be Ready; Cilium and CoreDNS must be healthy.

## Phase 5: Flux Bootstrap

Create a short-lived GitHub fine-grained PAT with:

```text
Repository:     homelab only
Administration: Read and write
Contents:       Read and write
Metadata:       Read-only
```

Run:

```bash
cd "$REPO_ROOT/ansible"
(
  read -rsp "GitHub fine-grained token: " GITHUB_TOKEN
  printf '\n'
  export GITHUB_TOKEN

  ../scripts/ansible-yubikey playbooks/platform-bootstrap.yml
)
```

Or replace the wrapper with `ansible-playbook`.

The subshell removes the variable. Revoke the token after successful bootstrap
or let its short expiration end.

Pull the generated Flux commit:

```bash
cd "$REPO_ROOT"
git pull --rebase origin main
```

## Phase 6: Kubernetes and Flux Acceptance

```bash
kubectl get nodes -o wide
kubectl get pods --all-namespaces
kubectl get kustomizations --namespace flux-system
kubectl get helmreleases --all-namespaces
```

All six Kustomizations must be `Ready=True`:

```text
flux-system
infrastructure-controllers
infrastructure-configs
applications
infrastructure-kubelet-csr-approver
infrastructure-metrics-server
```

If a HelmRelease exhausted retries while an earlier dependency was being
repaired, fix the cause first and then reset only that release:

```bash
flux reconcile helmrelease NAME \
  --namespace NAMESPACE \
  --reset \
  --timeout=10m
```

No reset should be required in a clean rebuild proof.

## Phase 7: Secrets, Certificates, and Metrics

```bash
kubectl get secret sops-age --namespace flux-system
kubectl get clustersecretstore
kubectl get externalsecret --all-namespaces
kubectl get clusterissuer
kubectl get certificate --all-namespaces
kubectl get certificatesigningrequests
kubectl top nodes
```

Require:

- `azure-key-vault` Ready
- every ExternalSecret Ready
- staging and production issuers Ready
- wildcard certificate Ready
- serving CSRs approved by the controller
- metrics for all three nodes

Do not print Kubernetes Secret `.data`.

## Phase 8: Ingress Acceptance

Verify static service values:

```bash
kubectl get service traefik \
  --namespace traefik \
  --output jsonpath='{.status.loadBalancer.ingress[0].ip}{"\n"}{range .spec.ports[*]}{.name}{" "}{.nodePort}{"\n"}{end}'
```

Expected:

```text
192.168.0.220
web 32492
websecure 30860
```

Diagnostic LAN route:

```bash
curl -vkI \
  --resolve grafana.mccruden.com:443:192.168.0.220 \
  https://grafana.mccruden.com
```

Diagnostic NodePort route:

```bash
curl -vkI \
  --resolve grafana.mccruden.com:30860:192.168.0.52 \
  https://grafana.mccruden.com:30860
```

Final acceptance:

```bash
curl -fsSI https://grafana.mccruden.com
```

The final command must succeed without `-k`.

## Phase 9: Idempotency

Run all three playbooks again without `GITHUB_TOKEN`:

```bash
cd "$REPO_ROOT/ansible"
../scripts/ansible-yubikey playbooks/system-init.yml
../scripts/ansible-yubikey playbooks/cluster-bootstrap.yml
../scripts/ansible-yubikey playbooks/platform-bootstrap.yml
```

Require:

```text
failed=0
unreachable=0
```

Record and explain unexpected repeated changes.

## Phase 10: Close the Proof

Record:

- final Git commit and Flux applied revision
- duration of each phase
- all six Kustomization conditions
- all HelmRelease conditions
- public HTTPS result
- idempotency result
- actual RTO
- any lost data and measured RPO
- every diagnostic command
- whether any undocumented mutation was required

If no durable manual repair was required, tag the commit as rebuild-proven.

If a repair was required:

1. do not call the build proven
2. identify the correct owner
3. update Terraform, Ansible, Flux, or the external prerequisite documentation
4. validate the change
5. repeat the rebuild proof when safe

## Failure Rule

Manual commands may diagnose a failed stage. They must not become invisible
prerequisites. The permanent fix belongs in code or in this documented external
preflight.
