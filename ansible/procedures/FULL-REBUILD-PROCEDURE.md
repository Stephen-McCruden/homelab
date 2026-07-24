# Full Rebuild Procedure

## Purpose

Recreate the Proxmox virtual machines, Fedora node state, Kubernetes cluster, Flux installation, SOPS bootstrap Secret, and Git-managed platform resources after a deliberate destroy or VM loss.

## Current Limit

This procedure restores infrastructure and declarative Kubernetes resources. It does not yet restore databases, uploads, PVC contents, or other persistent application data.

## Before Destroy

From the repository root:

```bash
cd /home/stoof/GitHub/homelab
git status
git pull --rebase origin main
```

Confirm:

- The working tree is clean.
- All desired changes are pushed.
- The correct HCP Terraform workspace is accessible.
- `terraform/terraform.tfvars` is available and ignored.
- Local Ansible inventory and group variables are available and ignored.
- The controller SSH private key is available.
- The SOPS age private key is available and backed up.
- Azure Key Vault still contains the required runtime secrets.
- Important persistent application data is backed up externally.
- Router forwarding is documented as `80 -> 192.168.0.52:32492` and `443 -> 192.168.0.52:30860`.

## Verify the SOPS Key Before Destruction

```bash
SOPS_KEY_PATH="${SOPS_AGE_KEY_FILE:-$HOME/.config/sops/age/keys.txt}"
test -s "$SOPS_KEY_PATH"
grep -q '^AGE-SECRET-KEY-' "$SOPS_KEY_PATH"
```

Verify it can decrypt the repository bootstrap credential:

```bash
sops --decrypt \
  kubernetes/infrastructure/configs/external-secrets/azure-credentials.sops.yaml \
  >/dev/null
```

## Create a Short-Lived GitHub Token

A fully destroyed cluster no longer has the Flux SSH deploy key Secret, so a new bootstrap token is required.

Configure the fine-grained token with:

```text
Repository access:  only homelab
Administration:     Read and write
Contents:           Read and write
Metadata:           Read-only
```

Do not place the token in a tracked file.

## Destroy and Recreate Virtual Machines

```bash
cd terraform
terraform plan -destroy
terraform destroy
terraform apply
```

Wait for cloud-init and SSH availability.

## Stage 1: System Initialization

```bash
cd ../ansible
```

Without a YubiKey:

```bash
ansible-playbook playbooks/system-init.yml
```

With YubiKey-backed SSH:

```bash
../scripts/ansible-yubikey playbooks/system-init.yml
```

## Stage 2: Kubernetes Bootstrap

Without a YubiKey:

```bash
ansible-playbook playbooks/cluster-bootstrap.yml
```

With YubiKey-backed SSH:

```bash
../scripts/ansible-yubikey playbooks/cluster-bootstrap.yml
```

## Stage 3: Load the GitHub Token

```bash
read -rsp "GitHub fine-grained token: " GITHUB_TOKEN
printf '\n'
export GITHUB_TOKEN
```

Confirm without printing it:

```bash
test -n "${GITHUB_TOKEN:-}" && echo "GITHUB_TOKEN is loaded"
```

## Stage 4: Platform Bootstrap

Without a YubiKey:

```bash
ansible-playbook playbooks/platform-bootstrap.yml
```

With YubiKey-backed SSH:

```bash
../scripts/ansible-yubikey playbooks/platform-bootstrap.yml
```

This stage creates `flux-system/sops-age` automatically before encrypted GitOps resources are reconciled.

Do not manually create the Secret.

## Remove the Token

```bash
unset GITHUB_TOKEN
test -z "${GITHUB_TOKEN:-}" && echo "GITHUB_TOKEN removed from this shell"
```

Revoke the token in GitHub after the rebuild succeeds or let its short expiration end.

## Pull the Flux Bootstrap Commit

```bash
cd /home/stoof/GitHub/homelab
git pull --rebase origin main
```

## Verify Kubernetes

```bash
export KUBECONFIG="$HOME/.kube/homelab-admin.conf"

kubectl get nodes -o wide
kubectl get pods -A
kubectl get --raw=/readyz
```

Expected nodes:

```text
k8s-master-01  Ready
k8s-worker-01  Ready
k8s-worker-02  Ready
```

## Verify Flux and SOPS

```bash
flux check
kubectl get kustomizations.kustomize.toolkit.fluxcd.io -A
kubectl get helmreleases.helm.toolkit.fluxcd.io -A
kubectl get secret sops-age -n flux-system
```

Expected Kustomizations:

```text
flux-system                 Ready=True
infrastructure-controllers  Ready=True
infrastructure-configs      Ready=True
applications                Ready=True
```

## Verify Platform Dependencies

```bash
kubectl get clustersecretstore
kubectl get externalsecret -A
kubectl get clusterissuer
kubectl get certificate -A
kubectl get service traefik -n traefik
```

Confirm Traefik:

```text
LoadBalancer IP:    192.168.0.220
HTTP NodePort:      32492
HTTPS NodePort:     30860
```

## Verify Grafana Ingress

MetalLB path:

```bash
curl -vkI \
  --resolve grafana.mccruden.com:443:192.168.0.220 \
  https://grafana.mccruden.com
```

Master-node NodePort path:

```bash
curl -vkI \
  --resolve grafana.mccruden.com:30860:192.168.0.52 \
  https://grafana.mccruden.com:30860
```

Public path:

```bash
curl -vkI https://grafana.mccruden.com
```

## Verify Idempotency

Run all three Ansible stages again without `GITHUB_TOKEN`.

Without a YubiKey:

```bash
cd ansible
ansible-playbook playbooks/system-init.yml
ansible-playbook playbooks/cluster-bootstrap.yml
ansible-playbook playbooks/platform-bootstrap.yml
```

With YubiKey-backed SSH:

```bash
cd ansible
../scripts/ansible-yubikey playbooks/system-init.yml
../scripts/ansible-yubikey playbooks/cluster-bootstrap.yml
../scripts/ansible-yubikey playbooks/platform-bootstrap.yml
```

Expected:

```text
failed=0
unreachable=0
```

## Rebuild Failure Rule

Do not compensate for a failed automated stage with undocumented manual changes.

Use manual commands only to diagnose the failure. Then update Terraform, Ansible, Flux manifests, or the documented external prerequisite so the next full rebuild succeeds without that manual intervention.

## Future Complete Recovery

The final recovery workflow will add a backup stage that reconnects external backup storage, restores persistent data, validates applications, and records RTO and RPO.
