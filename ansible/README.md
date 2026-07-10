# Homelab Ansible v1

Run the complete Fedora Kubernetes node baseline with:

```bash
ansible-playbook playbooks/system-init.yml
```

Run as the normal local user, not with `sudo`. The playbook uses privilege escalation only on managed nodes.

## v1.0.0-rc2 compatibility cleanup

This release candidate includes two final transport-level cleanup changes:

- SSH host-key reconciliation compares key algorithms and key material, so an unchanged Terraform node reports `ok` rather than `changed`.
- Fedora systemd OSC 3008 shell-context integration is disabled and masked before fact gathering because it appends terminal control sequences after Ansible module JSON when privilege escalation is used.
