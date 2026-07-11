# Homelab Ansible

This directory contains the three current deployment stages used after Terraform provisions Fedora VMs.

```bash
ansible-playbook playbooks/system-init.yml
ansible-playbook playbooks/cluster-bootstrap.yml
ansible-playbook playbooks/platform-bootstrap.yml
```

Run Ansible as the normal controller user. Remote privilege escalation is handled by the playbooks.

## Stage Responsibilities

### `system-init.yml`

Reconciles SSH host keys, validates Fedora/inventory/sudo, protects DNF5 transactions, installs Kubernetes tooling and containerd, configures kernel prerequisites, firewalld, SSH hardening, SELinux compatibility mode, and end-state verification.

### `cluster-bootstrap.yml`

Renders kubeadm configuration, initializes only when required, detects and joins only missing workers, generates temporary credentials only when needed, installs Cilium only when absent, and validates the API, nodes, CoreDNS, Cilium, and system Pods.

### `platform-bootstrap.yml`

Installs a pinned Flux CLI, performs GitHub bootstrap only when required, validates SSH deploy-key authentication, checks the Git branch, waits for controller rollouts, and verifies every managed Kustomization.

## Procedures

- [System initialization](procedures/SYSTEM-INIT-PROCEDURE.md)
- [Cluster bootstrap](procedures/CLUSTER-BOOTSTRAP-PROCEDURE.md)
- [Platform bootstrap](procedures/PLATFORM-BOOTSTRAP-PROCEDURE.md)
- [Full rebuild](procedures/FULL-REBUILD-PROCEDURE.md)

## Templates

- `inventory/hosts.yml.example`
- `inventory/group_vars/all.yml.example`
- `platform-bootstrap.env.example`

## Validation

```bash
cd ansible
ansible-inventory --graph

ansible-playbook playbooks/system-init.yml --syntax-check
ansible-playbook playbooks/cluster-bootstrap.yml --syntax-check
ansible-playbook playbooks/platform-bootstrap.yml --syntax-check

ansible-lint playbooks/system-init.yml
ansible-lint playbooks/cluster-bootstrap.yml
ansible-lint playbooks/platform-bootstrap.yml

yamllint .
```

## Runtime Idempotency

```bash
ansible-playbook playbooks/system-init.yml
ansible-playbook playbooks/cluster-bootstrap.yml
ansible-playbook playbooks/platform-bootstrap.yml
```

A healthy existing deployment should report:

```text
changed=0
failed=0
```

## Kubeconfig

```text
~/.kube/homelab-admin.conf
```

```bash
export KUBECONFIG="$HOME/.kube/homelab-admin.conf"
```

This file grants administrative access and must not be committed.

## Security Decisions

- GPG verification remains enabled.
- SSH password authentication is disabled only after key verification.
- Firewall access is source restricted.
- Join credentials are temporary.
- The GitHub PAT is never stored in Git.
- Flux uses a generated SSH deploy key after bootstrap.
- SELinux permissive mode is a documented Fedora compatibility workaround.

## Planned Fourth Stage

`backup-bootstrap.yml` will provide external backup credentials and controlled restore/verification operations. Backup schedules and most backup resources will remain GitOps-managed.
