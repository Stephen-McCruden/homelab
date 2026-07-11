# System Initialization Procedure

## Purpose

Converge fresh Terraform-provisioned Fedora nodes into a validated Kubernetes node baseline.

## Preconditions

- Terraform completed successfully.
- All three VMs are reachable over SSH.
- Inventory addresses match Terraform.
- The configured private key matches an injected public key.
- The remote user has passwordless sudo.
- Commands are run from `ansible/`.

## Preflight

```bash
cd /home/stoof/GitHub/homelab/ansible
ansible-inventory --graph
ansible all -m ping
ansible-playbook playbooks/system-init.yml --syntax-check
ansible-lint playbooks/system-init.yml
```

## Execute

```bash
ansible-playbook playbooks/system-init.yml
```

## Expected Actions

- Reconcile controller `known_hosts`
- Validate Fedora and inventory
- Suppress conflicting automatic DNF jobs
- Install prerequisites
- Configure kernel modules, sysctls, swap, and zram
- Install and configure containerd
- Install Kubernetes packages
- Configure firewalld and SSH hardening
- Configure SELinux permissive mode
- Verify resulting state

## Idempotency

```bash
ansible-playbook playbooks/system-init.yml
```

Expected:

```text
changed=0
failed=0
unreachable=0
```

## DNF5 Behavior

The package-manager role disables `dnf-makecache.timer`, stops stale automatic makecache processes, serializes sensitive package transactions, retains GPG verification, and removes cached payloads only after a real transaction failure.

Do not add an unconditional `dnf5 makecache --refresh`.

## SELinux

SELinux remains enabled but permissive so AVC denials remain auditable while kubeadm static Pods operate.

## Failure Handling

- **Unreachable:** check routing, TCP 22, username, key path, injected key, and cloud-init.
- **Sudo failure:** configure noninteractive passwordless sudo.
- **Package signature failure:** allow the recovery block to complete; do not disable GPG.
- **Partial convergence:** correct the cause and rerun the same playbook.
