# Ansible: Fedora and Kubernetes Bootstrap

Ansible owns the node operating-system baseline, kubeadm cluster bootstrap,
Cilium installation, secure kubelet serving certificates, local kubeconfig
retrieval, Flux bootstrap, and deployment verification.

Run Ansible as the normal controller user. The playbooks request remote
privilege escalation where required.

## Stages

```bash
ansible-playbook playbooks/system-init.yml
ansible-playbook playbooks/cluster-bootstrap.yml
ansible-playbook playbooks/platform-bootstrap.yml
```

YubiKey:

```bash
../scripts/ansible-yubikey playbooks/system-init.yml
../scripts/ansible-yubikey playbooks/cluster-bootstrap.yml
../scripts/ansible-yubikey playbooks/platform-bootstrap.yml
```

## Stage Responsibilities

### `system-init.yml`

- reconcile host keys after VM replacement
- validate inventory, Fedora, and passwordless sudo
- serialize DNF5 transactions
- configure kernel modules, sysctls, swap, and zram
- install containerd and Kubernetes packages
- configure explicit firewalld rules
- harden SSH
- set the documented SELinux compatibility state
- verify the node baseline

### `cluster-bootstrap.yml`

- render kubeadm v1beta4 configuration
- initialize the single control plane only when required
- retrieve the administrative kubeconfig
- prepare every node for Cilium
- join only missing workers with temporary credentials
- persist and reconcile secure kubelet serving-certificate bootstrap
- install version-pinned Cilium
- verify nodes, API, CoreDNS, Cilium, and system Pods

### `platform-bootstrap.yml`

- validate the API and admin kubeconfig
- install and checksum-verify the pinned Flux CLI
- validate the controller SOPS age identity
- create or update `flux-system/sops-age`
- bootstrap Flux only when absent
- verify the generated SSH deploy-key Secret
- wait for the Git source and all six managed Kustomizations
- run the final Flux health check

## Inventory

Reference files are intentionally tracked:

```text
inventory/hosts.yml
inventory/group_vars/all.yml
```

They contain topology and local paths, not secret values. A reproducer should
adapt them and use the `*.example` files as a checklist.

```bash
ansible-inventory --graph
ansible-inventory --host k8s-master-01
```

## Validation

```bash
ansible-playbook playbooks/system-init.yml --syntax-check
ansible-playbook playbooks/cluster-bootstrap.yml --syntax-check
ansible-playbook playbooks/platform-bootstrap.yml --syntax-check

ansible-lint --profile min playbooks/system-init.yml
ansible-lint --profile min playbooks/cluster-bootstrap.yml
ansible-lint --profile min playbooks/platform-bootstrap.yml

yamllint .
```

The minimum lint profile currently passes. Newer default/strict profiles also
report existing style debt in older roles: role-variable prefixes, two
reload-as-handler suggestions, and `run_once` strategy warnings. Resolve those
in a dedicated role refactor rather than mixing behavioral changes into a
rebuild or documentation update.

## First Platform Bootstrap

```bash
(
  read -rsp "GitHub fine-grained token: " GITHUB_TOKEN
  printf '\n'
  export GITHUB_TOKEN

  ../scripts/ansible-yubikey playbooks/platform-bootstrap.yml
)
```

The token is unnecessary on healthy later runs. The SOPS identity remains
required because the playbook verifies and enforces the bootstrap Secret.

## Idempotency Contract

Every successful playbook must be safe to run again:

```text
failed=0
unreachable=0
```

Expected state-aware behavior:

- kubeadm init is skipped on an initialized control plane
- joined workers are not rejoined
- an unused join token is not generated
- Cilium is not reinstalled unnecessarily
- Flux is not bootstrapped again
- the SOPS Secret is reconciled without exposing its value
- health validation always runs

Investigate unexplained repeated changes.

## Kubeconfig

Expected controller path:

```text
~/.kube/homelab-admin.conf
```

```bash
chmod 600 "$HOME/.kube/homelab-admin.conf"
export KUBECONFIG="$HOME/.kube/homelab-admin.conf"
```

## Security Decisions

- package signature verification remains enabled
- SSH password authentication is disabled only after key validation
- firewall sources and ports are explicit
- kubeadm join credentials are short-lived and generated only when needed
- kubelet serving certificates use normal CA validation
- the GitHub PAT is temporary; Flux later uses a read-only deploy key
- the SOPS identity remains outside Git and is transferred temporarily
- SELinux remains enabled but permissive until the blocking policy is resolved

## Procedures

- [System initialization](procedures/SYSTEM-INIT-PROCEDURE.md)
- [Cluster bootstrap](procedures/CLUSTER-BOOTSTRAP-PROCEDURE.md)
- [Platform bootstrap](procedures/PLATFORM-BOOTSTRAP-PROCEDURE.md)
- [Full rebuild](procedures/FULL-REBUILD-PROCEDURE.md)
- [Troubleshooting](../docs/TROUBLESHOOTING.md)
