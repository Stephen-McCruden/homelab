# System Initialization Procedure

## Purpose

Converge fresh Terraform-provisioned Fedora nodes into a validated Kubernetes node baseline.

## Preconditions

- Terraform completed successfully.
- All three VMs are reachable over SSH.
- Inventory addresses match Terraform.
- The configured private key matches a public key injected by Terraform.
- The remote user has noninteractive passwordless sudo.
- Commands are run from `ansible/`.

## Preflight

```bash
cd /home/stoof/GitHub/homelab/ansible
ansible-inventory --graph
ansible-playbook playbooks/system-init.yml --syntax-check
ansible-lint playbooks/system-init.yml
```

### Standard SSH key test

```bash
ansible all -m ping
```

### YubiKey-backed SSH test

The wrapper runs `ansible-playbook`, so use direct SSH for the preflight connection test:

```bash
ssh -o IdentitiesOnly=yes \
  -i "$HOME/.ssh/id_ed25519_sk" \
  stoof@192.168.0.52 true
```

## Execute

Without a YubiKey:

```bash
ansible-playbook playbooks/system-init.yml
```

With YubiKey-backed SSH:

```bash
../scripts/ansible-yubikey playbooks/system-init.yml
```

## Expected Actions

- Reconcile controller `known_hosts` entries.
- Validate Fedora, inventory, and sudo.
- Stop or suppress conflicting automatic DNF metadata jobs.
- Install prerequisites.
- Configure kernel modules and sysctls.
- Disable swap and zram.
- Install and configure containerd.
- Install Kubernetes packages.
- Configure firewalld.
- Apply SSH hardening.
- Configure SELinux permissive mode.
- Verify the resulting state.

## Idempotency

Run the same command again.

Expected:

```text
failed=0
unreachable=0
```

Most tasks should report `ok`. Investigate unexpected changes.

## DNF5 Behavior

The package-manager role disables or stops conflicting metadata jobs, serializes sensitive package operations, keeps GPG verification enabled, and performs cleanup only after an actual transaction failure.

Do not add an unconditional:

```bash
dnf5 makecache --refresh
```

## SELinux

SELinux remains enabled but permissive. AVC denials remain available for review, but enforcing protection is not active on the Kubernetes nodes.

## Failure Handling

### Unreachable node

Check:

- Routing and TCP 22.
- Inventory address and username.
- Controller private-key path.
- Injected public key.
- cloud-init completion.
- Old `known_hosts` entries.

### YubiKey prompt failure

Check:

- The key path.
- YubiKey insertion.
- `SSH_ASKPASS` path.
- PIN entry.
- Physical touch.
- That the matching public key was injected by Terraform.

### Sudo failure

Configure noninteractive passwordless sudo for the automation user.

### Package failure

Allow the role's recovery block to complete. Do not disable package signature verification.

### Partial convergence

Correct the cause and rerun the same playbook. Do not manually repeat only the failed shell command unless troubleshooting requires it.
