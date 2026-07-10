# FILE PATH: README.md
# Homelab Ansible

Production-style Fedora Kubernetes node automation for Terraform-created Proxmox VMs.

## Normal operation

```bash
ansible-playbook playbooks/system-init.yml
```

This single playbook reconciles ephemeral SSH host keys, configures package management, prerequisites, containerd, Kubernetes tools, firewalling, hardening, and verifies the final state.

## Repository layout

- `playbooks/`: operational entry points
- `roles/`: reusable configuration units
- `inventory/`: environment inventory
- `procedures/`: operator runbooks
- `docs/ADR/`: architecture decisions
- `.github/workflows/`: automated static validation

## Controller setup
Normal operation requires only Ansible Core on the controller. The operational playbook uses built-in modules and does not require Galaxy collections. Development-only lint and CI tools are installed with `make install`.

## Lifecycle boundary
`system-init.yml` prepares nodes only. `kube-bootstrap.yml`, upgrades, and destructive reset automation remain gated until their own procedures are designed and tested.

## Automated testing
GitHub Actions runs YAML linting, Ansible linting, syntax validation, and a privileged Fedora Molecule scenario. Molecule's built-in idempotence phase converges the tested roles a second time and fails when tasks still report changes.
