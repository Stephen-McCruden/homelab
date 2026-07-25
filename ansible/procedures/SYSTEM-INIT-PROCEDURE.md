# System Initialization Procedure

## Purpose

Converge fresh Terraform-provisioned Fedora VMs into a validated Kubernetes
node baseline.

## Preconditions

- Terraform completed successfully.
- All three VMs are reachable over SSH.
- inventory names and addresses match Terraform.
- the selected private identity matches a Terraform-injected public key.
- the remote user has noninteractive passwordless sudo.
- commands run from the repository's `ansible/` directory.

## Preflight

```bash
cd /path/to/homelab/ansible

ansible-inventory --graph
ansible-playbook playbooks/system-init.yml --syntax-check
ansible-lint --profile min playbooks/system-init.yml
yamllint playbooks/system-init.yml roles
```

File-backed SSH:

```bash
ansible kubernetes_cluster --module-name ping
```

YubiKey:

```bash
ssh -o IdentitiesOnly=yes \
  -i "$HOME/.ssh/id_ed25519_sk" \
  stoof@192.168.0.52 true
```

Repeat direct SSH for both workers.

## Execute

YubiKey:

```bash
../scripts/ansible-yubikey playbooks/system-init.yml
```

File-backed key:

```bash
ansible-playbook playbooks/system-init.yml
```

## Expected Work

1. reconcile controller `known_hosts`
2. validate Fedora, inventory, and sudo
3. control competing DNF5 metadata jobs
4. install prerequisites
5. configure kernel modules and sysctls
6. disable swap and zram
7. install and configure containerd
8. install Kubernetes packages
9. configure firewalld
10. harden SSH
11. set SELinux permissive
12. verify final state

## Acceptance

The playbook's verification role is authoritative. Additional checks:

```bash
ansible kubernetes_cluster \
  --become \
  --module-name command \
  --args='systemctl is-active containerd kubelet firewalld'

ansible kubernetes_cluster \
  --become \
  --module-name command \
  --args='swapon --show'
```

The services should be active and the swap output empty.

## Idempotency

Run the same command again. Require:

```text
failed=0
unreachable=0
```

Investigate repeated package transactions, service restarts, regenerated
configuration, or firewall churn.

## Important Decisions

### DNF5

The package role serializes sensitive transactions, keeps GPG verification
enabled, and performs recovery only after a real failure.

Do not add:

```bash
dnf5 makecache --refresh
```

as an unconditional task.

### SELinux

SELinux remains enabled in permissive mode because Fedora policy currently
blocks required Kubernetes static-Pod behavior in enforcing mode. AVCs remain
available for future policy work.

### Firewall

The firewall role owns node and Pod-to-host rules. A manual `firewall-cmd`
change is a diagnostic only and will not survive a rebuild unless encoded in
the role.

## Failure Isolation

### Unreachable

Check route, TCP `22`, inventory, username, SSH key, cloud-init, and stale host
keys.

### YubiKey prompt

Check key insertion, identity path, PIN, physical touch, askpass, and whether
the matching public key was injected.

### Sudo

The automation user requires noninteractive passwordless sudo.

### Package transaction

Inspect DNF/RPM processes and systemd jobs. Allow the role's bounded recovery to
complete; do not disable signature verification.

### Partial convergence

Correct the cause and rerun the full playbook. Do not turn the failed shell
command into an undocumented one-off installation step.

Continue with [Cluster bootstrap](CLUSTER-BOOTSTRAP-PROCEDURE.md).
