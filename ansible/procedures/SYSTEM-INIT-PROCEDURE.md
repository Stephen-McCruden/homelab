> **FILE PATH:** `procedures/SYSTEM-INIT-PROCEDURE.md`  
> Keep this file at exactly this path inside the Ansible project.

# Kubernetes Node System-Initialization Procedure

## Purpose

This procedure prepares Terraform-provisioned Fedora virtual machines as hardened Kubernetes nodes. It also reconciles SSH host keys on the Ansible controller before connecting, which supports repeated Terraform destroy/apply cycles that reuse the same IP addresses.

It does not run `kubeadm init` or join nodes. Cluster creation belongs in a later playbook or role.

## File placement

Keep the repository structure unchanged. Several files are named `main.yml` because Ansible roles use standard directory entry points. See `FILE-MAP.md` for the exact path and purpose of every file.

## Normal operation

From the repository root, run only:

```bash
ansible-playbook system-init.yml
```

The playbook performs controller SSH-key reconciliation, host preflight checks, prerequisite configuration, hardening, handler execution, and verification.

## Terraform rebuild behavior

Terraform already places the operator's public SSH key in each VM. That solves user authentication, but a rebuilt VM generates a new SSH host key. Because the IP is reused, the old key in `~/.ssh/known_hosts` would normally cause an SSH host-identification failure before Ansible can connect.

The first localhost play in `system-init.yml` handles this automatically:

1. It scans the currently reachable ED25519 host key for every `ansible_host`.
2. It compares that key with the controller's existing `known_hosts` entry.
3. It leaves a matching entry untouched.
4. It removes and replaces the entry only when it is absent or different.
5. The remote configuration play then connects with normal host-key checking still enabled.

This is idempotent when the VM has not changed. A stable host key produces no controller change.

### Security note

`ssh-keyscan` discovers the live key but does not cryptographically prove the VM's identity. Automatic replacement is appropriate for this controlled ephemeral homelab workflow, but it trades manual fingerprint validation for unattended rebuilds. Keep `reconcile_ephemeral_ssh_host_keys: true` only for networks and provisioning paths you control.

## Tailscale access

The inventory connects to the VMs by their LAN addresses. The laptop reaches those addresses through the Proxmox Tailscale subnet router.

Tailscale subnet routers use SNAT by default. In that default mode, each VM sees the connection as coming from the subnet router's LAN address. Therefore this is sufficient:

```yaml
management_network_cidrs:
  - 192.168.0.0/24

tailscale_management_cidrs: []
```

If subnet-route SNAT is deliberately disabled, the VM can see the laptop's source address. Add only the laptop's exact Tailscale address as a `/32`:

```yaml
tailscale_management_cidrs:
  - 100.x.y.z/32
```

Avoid allowing all of `100.64.0.0/10` unless every tailnet device should be permitted to attempt SSH access. Tailscale ACL or grants should also restrict who can reach the Kubernetes subnet.

## Preconditions

- Ansible Core 2.16 or newer is installed on the laptop/controller.
- `ssh-keyscan` and `ssh-keygen` are installed on the controller.
- Tailscale is connected and the advertised `192.168.0.0/24` route is accepted.
- Terraform has completed successfully.
- The VM public keys and passwordless sudo configuration are present.
- The Fedora nodes have outbound DNS and HTTPS access.
- `inventory/hosts.yml` contains the current Terraform addresses.

## Success criteria

The run must finish without failed hosts. Verification confirms swap, kernel modules, sysctls, containerd, Kubernetes packages, SELinux, firewalld, SSH settings, services, and permitted management sources.

A second run against unchanged infrastructure should normally report no remote changes. The SSH reconciliation step also remains unchanged when host keys match.

## Failure recovery

Correct the underlying Terraform, route, DNS, SSH, sudo, package repository, or node configuration issue and rerun the same command:

```bash
ansible-playbook system-init.yml
```

Do not manually skip ahead. Completed tasks are designed to be safely rerun.
