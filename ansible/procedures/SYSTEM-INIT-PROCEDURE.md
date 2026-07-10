# System Initialization Procedure

1. Provision the VMs with Terraform.
2. Review `inventory/hosts.yml` and `inventory/group_vars/all.yml`.
3. From the Ansible repository root, run:

```bash
ansible-playbook playbooks/system-init.yml
```

4. Run the same command a second time to test idempotency.
