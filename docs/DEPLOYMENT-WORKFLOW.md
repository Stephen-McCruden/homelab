# Deployment Workflow

This guide gives the normal deployment order. Detailed checks and failure handling are in the individual procedures.

## 1. Prepare Local Configuration

From the repository root:

```bash
cp -n terraform/terraform.tfvars.example \
  terraform/terraform.tfvars

cp -n ansible/inventory/hosts.yml.example \
  ansible/inventory/hosts.yml

cp -n ansible/inventory/group_vars/all.yml.example \
  ansible/inventory/group_vars/all.yml
```

Protect and verify the Terraform variable file:

```bash
chmod 600 terraform/terraform.tfvars
git check-ignore -v terraform/terraform.tfvars
```

Review every placeholder before continuing.

## 2. Verify Controller Credentials

### SSH with YubiKey

```bash
test -f "$HOME/.ssh/id_ed25519_sk"
test -f "$HOME/.ssh/id_ed25519_sk.pub"
```

### SSH without YubiKey

```bash
test -f "$HOME/.ssh/id_ed25519"
chmod 600 "$HOME/.ssh/id_ed25519"
```

### SOPS age key

```bash
SOPS_KEY_PATH="${SOPS_AGE_KEY_FILE:-$HOME/.config/sops/age/keys.txt}"
test -s "$SOPS_KEY_PATH"
grep -q '^AGE-SECRET-KEY-' "$SOPS_KEY_PATH"
```

## 3. Provision Virtual Machines

```bash
cd terraform
terraform login
terraform init
terraform fmt -recursive
terraform validate
terraform plan
terraform apply
```

Confirm SSH reachability after cloud-init finishes.

## 4. Initialize Fedora Nodes

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

## 5. Build Kubernetes

Without a YubiKey:

```bash
ansible-playbook playbooks/cluster-bootstrap.yml
```

With YubiKey-backed SSH:

```bash
../scripts/ansible-yubikey playbooks/cluster-bootstrap.yml
```

## 6. Load the GitHub Token for First Flux Bootstrap

A completely new cluster requires a GitHub fine-grained token. A healthy existing Flux installation does not.

```bash
read -rsp "GitHub fine-grained token: " GITHUB_TOKEN
printf '\n'
export GITHUB_TOKEN
```

Confirm it exists without printing it:

```bash
test -n "${GITHUB_TOKEN:-}" && echo "GITHUB_TOKEN is loaded"
```

The token permissions are:

```text
Administration: Read and write
Contents:       Read and write
Metadata:       Read-only
```

Repository access should be limited to the homelab repository.

## 7. Bootstrap Flux and Create the SOPS Secret

Without a YubiKey:

```bash
ansible-playbook playbooks/platform-bootstrap.yml
```

With YubiKey-backed SSH:

```bash
../scripts/ansible-yubikey playbooks/platform-bootstrap.yml
```

The playbook now creates `flux-system/sops-age` automatically before Flux applies encrypted configuration.

Do not run a separate manual `kubectl create secret` command.

## 8. Remove the Token

```bash
unset GITHUB_TOKEN
test -z "${GITHUB_TOKEN:-}" && echo "GITHUB_TOKEN removed from this shell"
```

The GitHub token still exists on GitHub until it expires or is revoked.

## 9. Pull the Flux Bootstrap Commit

Flux commits bootstrap manifests to the repository during the first bootstrap.

```bash
cd ..
git pull --rebase origin main
```

Review the generated `clusters/homelab/flux-system/` files before making unrelated changes.

## 10. Verify the Platform

```bash
export KUBECONFIG="$HOME/.kube/homelab-admin.conf"

kubectl get nodes -o wide
kubectl get pods -A
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

Verify the SOPS Secret without exposing its value:

```bash
kubectl get secret sops-age -n flux-system
```

Verify Traefik's static ports:

```bash
kubectl get service traefik -n traefik \
  -o jsonpath='{range .spec.ports[*]}{.name}{" "}{.nodePort}{"\n"}{end}'
```

Expected NodePorts:

```text
HTTP  32492
HTTPS 30860
```

## 11. Verify Ingress

Directly through the Traefik LoadBalancer address:

```bash
curl -vkI \
  --resolve grafana.mccruden.com:443:192.168.0.220 \
  https://grafana.mccruden.com
```

Directly through the master NodePort:

```bash
curl -vkI \
  --resolve grafana.mccruden.com:30860:192.168.0.52 \
  https://grafana.mccruden.com:30860
```

Normal external path:

```bash
curl -vkI https://grafana.mccruden.com
```

A Grafana response normally redirects to `/login`.

## 12. Verify Idempotency

Run each stage again.

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

The second platform run does not require `GITHUB_TOKEN` when Flux is already bootstrapped.

A healthy second run should report:

```text
failed=0
unreachable=0
```

Most tasks should report `ok`. Tasks that enforce generated or time-sensitive state may still need review if they report `changed`.

## Normal Change Workflow

### Terraform changes

```bash
cd terraform
terraform fmt -recursive
terraform validate
terraform plan
terraform apply
```

### Ansible changes

Run the affected playbook, correct errors, and run it again to check idempotency.

### Kubernetes changes

Edit files under `clusters/` or `kubernetes/`, validate them, commit, and push. Flux reconciles the desired state.

Manual `flux reconcile` commands are troubleshooting tools. They should not be required during a normal rebuild.
