# Deployment Workflow

Use this document to understand stage order and acceptance gates. During an
actual replacement, use the
[full rebuild procedure](../ansible/procedures/FULL-REBUILD-PROCEDURE.md),
which is the canonical command-by-command runbook.

## Working Directory

Clone the repository wherever desired and derive its path:

```bash
git clone "git@github.com:<GITHUB_OWNER>/<REPOSITORY>.git"
cd homelab
REPO_ROOT="$(pwd)"
```

The procedures derive the checkout path and do not depend on a particular home
directory.

## Stage Gates

| Stage | Command owner | Gate before continuing |
|---|---|---|
| External preflight | Operator | Proxmox, network, state, secrets, and recovery inputs verified |
| Terraform | `terraform/` | All three VMs exist, cloud-init completed, and SSH works |
| System initialization | Ansible | Fedora baseline passes and second run is safe |
| Cluster bootstrap | Ansible | All nodes, Cilium, CoreDNS, and API are healthy |
| Platform bootstrap | Ansible and Flux | Every expected Kustomization and HelmRelease is Ready |
| Storage and secrets | Operator | Longhorn, PVCs, SecretStores, and ExternalSecrets are healthy |
| Endpoint acceptance | Operator | Public and Tailscale-private HTTPS endpoints respond |
| Rebuild proof | Operator | No undocumented repair was required |

Never continue merely because a command exited after a timeout. Verify the
stage's end state.

## 1. Validate External Inputs

Complete:

- [Environment setup](ENVIRONMENT-SETUP.md)
- [Configuration and secrets](CONFIGURATION-AND-SECRETS.md)
- [Controller authentication](CONTROLLER-AUTHENTICATION.md)

Confirm Git state:

```bash
git status --short
git pull --ff-only origin main
git rev-parse HEAD
```

Record the commit used for the deployment.

## 2. Validate the Repository

```bash
cd "$REPO_ROOT/terraform"
terraform fmt -check -recursive
terraform init
terraform validate

cd "$REPO_ROOT/ansible"
ansible-inventory --graph
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
kubectl kustomize kubernetes/infrastructure/controllers/tailscale >/dev/null
kubectl kustomize kubernetes/infrastructure/configs >/dev/null
kubectl kustomize kubernetes/infrastructure/configs/tailscale-ingress >/dev/null
kubectl kustomize kubernetes/applications/homelab >/dev/null
kubectl kustomize "<WEBSITE_AUTOMATION_PATH>" >/dev/null
```

Encrypted SOPS files can prevent a generic YAML parser from reading their
ciphertext as normal manifests. Validate them through SOPS:

```bash
sops --decrypt \
  kubernetes/infrastructure/configs/external-secrets/azure-credentials.sops.yaml \
  >/dev/null
```

## 3. Provision VMs

```bash
cd "$REPO_ROOT/terraform"
terraform plan -out=tfplan
terraform apply tfplan
```

Review the plan before applying. Do not keep `tfplan` in Git.

Gate:

```bash
NODE_ADDRESSES=("<WORKER_1_IP>" "<WORKER_2_IP>" "<CONTROL_PLANE_IP>")

for address in "${NODE_ADDRESSES[@]}"; do
  ping -c 2 "$address"
done
```

Then test SSH with the selected identity. Ping alone is not sufficient.

See the
[Terraform provisioning procedure](../terraform/procedures/TERRAFORM-PROVISIONING-PROCEDURE.md).

## 4. Initialize Fedora Nodes

```bash
cd "$REPO_ROOT/ansible"
../scripts/ansible-yubikey playbooks/system-init.yml
```

Or:

```bash
ansible-playbook playbooks/system-init.yml
```

Gate:

```bash
ansible kubernetes_cluster --module-name command \
  --args='systemctl is-active containerd kubelet firewalld'
```

The complete validation is performed by the playbook. See
[System initialization](../ansible/procedures/SYSTEM-INIT-PROCEDURE.md).

## 5. Bootstrap Kubernetes

```bash
../scripts/ansible-yubikey playbooks/cluster-bootstrap.yml
```

Or:

```bash
ansible-playbook playbooks/cluster-bootstrap.yml
```

Load the retrieved kubeconfig:

```bash
export KUBECONFIG="$HOME/.kube/homelab-admin.conf"
```

Gate:

```bash
kubectl get nodes -o wide
kubectl get --raw=/readyz
kubectl get pods --namespace kube-system
```

All three nodes must be Ready. CoreDNS and Cilium must be healthy before Flux
bootstrap.

See [Cluster bootstrap](../ansible/procedures/CLUSTER-BOOTSTRAP-PROCEDURE.md).

## 6. Bootstrap the Platform

For a new cluster:

```bash
(
  read -rsp "GitHub fine-grained token: " GITHUB_TOKEN
  printf '\n'
  export GITHUB_TOKEN

  ../scripts/ansible-yubikey playbooks/platform-bootstrap.yml
)
```

Or replace the wrapper with `ansible-playbook`.

The playbook:

1. checks the Kubernetes API
2. installs the pinned Flux CLI
3. provisions `flux-system/sops-age`
4. bootstraps Flux when absent
5. waits for the source and the six Kustomizations currently listed in the
   Ansible role
6. runs `flux check`

Flux then continues through the Tailscale and website-automation
Kustomizations. Use the repository-wide checks in the next stage before calling
the platform healthy.

Pull the commit generated by a first Flux bootstrap:

```bash
cd "$REPO_ROOT"
git pull --rebase origin main
```

See [Platform bootstrap](../ansible/procedures/PLATFORM-BOOTSTRAP-PROCEDURE.md).

## 7. Verify the Complete Platform

```bash
kubectl get kustomizations --namespace flux-system
kubectl get helmreleases --all-namespaces
kubectl get clustersecretstore
kubectl get externalsecret --all-namespaces
kubectl get clusterissuer
kubectl get certificate --all-namespaces
kubectl get certificatesigningrequests
kubectl top nodes
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

Verify Longhorn and stateful workloads:

```bash
kubectl get storageclass
kubectl get nodes.longhorn.io,volumes.longhorn.io \
  --namespace longhorn-system
kubectl get persistentvolumeclaim --all-namespaces
```

## 8. Verify Public and Private Endpoints

Set local shell variables to values selected during environment setup:

```bash
PUBLIC_HOSTNAME="<PUBLIC_HOSTNAME>"
TRAEFIK_VIP="<TRAEFIK_VIP>"
CONTROL_PLANE_IP="<CONTROL_PLANE_IP>"
TRAEFIK_HTTPS_NODEPORT="<TRAEFIK_HTTPS_NODEPORT>"
TAILNET_DOMAIN="<TAILNET_DOMAIN>"
```

Diagnostic LAN test:

```bash
curl -vkI \
  --resolve "${PUBLIC_HOSTNAME}:443:${TRAEFIK_VIP}" \
  "https://${PUBLIC_HOSTNAME}"
```

Diagnostic NodePort test:

```bash
curl -vkI \
  --resolve \
    "${PUBLIC_HOSTNAME}:${TRAEFIK_HTTPS_NODEPORT}:${CONTROL_PLANE_IP}" \
  "https://${PUBLIC_HOSTNAME}:${TRAEFIK_HTTPS_NODEPORT}"
```

Acceptance test:

```bash
curl -fsSI "https://${PUBLIC_HOSTNAME}"
curl -fsSI "https://homepage.${TAILNET_DOMAIN}"
curl -fsSI "https://linkding.${TAILNET_DOMAIN}"
curl -fsSI "https://grafana.${TAILNET_DOMAIN}"
```

`-k` is allowed for isolating a route. It is not an acceptable final TLS test.

## 9. Verify Idempotency

Run all three Ansible playbooks again without `GITHUB_TOKEN`:

```bash
cd "$REPO_ROOT/ansible"
../scripts/ansible-yubikey playbooks/system-init.yml
../scripts/ansible-yubikey playbooks/cluster-bootstrap.yml
../scripts/ansible-yubikey playbooks/platform-bootstrap.yml
```

Expected recap:

```text
failed=0
unreachable=0
```

Review unexpected `changed` tasks. Some reconciliation tasks can legitimately
change generated state, but repeated churn must be explained.

## Normal Change Workflow

### Terraform

```bash
terraform fmt -recursive
terraform validate
terraform plan
terraform apply
```

### Ansible

Run syntax and lint checks, execute the affected playbook, and execute it a
second time.

### Kubernetes

```bash
kubectl kustomize PATH >/dev/null
git diff --check
git add PATHS
git commit
git push
```

Flux owns the apply. Manual `kubectl apply` is for controlled diagnosis, not
normal deployment.

## Recording a Rebuild Proof

Record:

- Git commit
- start and finish time for every stage
- first failed automated task, if any
- all diagnostic commands
- whether a permanent manual mutation was used
- final acceptance results
- observed RTO

A rebuild is proven only when the desired commit reaches the healthy definition
without an undocumented corrective mutation.
