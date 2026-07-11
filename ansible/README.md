# Homelab Ansible v1
=======
This directory prepares Fedora Kubernetes nodes created by Terraform. It installs prerequisites, configures containerd 2.x, installs Kubernetes tools, applies firewall and SSH hardening, and validates the resulting state.

```bash
ansible-playbook playbooks/system-init.yml
```

Run the playbook as the normal controller user, never with `sudo`.

## Design guarantees

- No unconditional `dnf5 makecache --refresh` calls
- GPG verification remains enabled
- Package cache recovery happens only after transaction failure
- Controller SSH host-key reconciliation supports Terraform rebuilds
- Remote privilege escalation is scoped to the managed-node play
- Second-run idempotency is a release requirement
