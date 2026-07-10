> **FILE PATH:** `README.md`  
> Keep this file at exactly this path inside the Ansible project.

# Fedora Kubernetes Node Baseline

Run one command from this directory:

```bash
ansible-playbook system-init.yml
```

The playbook automatically reconciles SSH host keys for Terraform-recreated nodes, configures prerequisites, applies host hardening, and verifies the result.

Read `FILE-MAP.md` for exact file placement and `procedures/SYSTEM-INIT-PROCEDURE.md` for operating details, Tailscale behavior, rebuild handling, and security notes.
