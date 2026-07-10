# FILE PATH: procedures/SYSTEM-INIT-PROCEDURE.md
# System Initialization Procedure

## Purpose
Apply the repeatable Fedora Kubernetes-node baseline after Terraform creates or recreates the VMs.

## Preconditions
- Terraform completed successfully.
- The laptop can route to each VM through the Tailscale subnet router.
- Terraform injected the public SSH key for `ansible_user`.
- Ansible collections in `requirements.yml` are installed on the controller.

## Normal execution
From the repository root:

```bash
ansible-playbook playbooks/system-init.yml
```

The playbook reconciles changed SSH host keys, configures all nodes, hardens them, and performs verification.

## Rebuild workflow
```bash
terraform destroy
terraform apply
ansible-playbook playbooks/system-init.yml
```

## Idempotency acceptance test
Run `system-init.yml` twice. The second run should report `changed=0` unless package metadata, host keys, or an externally modified setting genuinely changed.

## Failure handling
Do not bypass GPG validation or disable SELinux. Correct the failing repository, package cache, networking, or policy condition and rerun the same playbook.
