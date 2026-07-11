# File Map

- `ansible.cfg` — controller configuration
- `inventory/hosts.yml` — Kubernetes node inventory
- `inventory/group_vars/all.yml` — shared connection and cluster variables
- `playbooks/system-init.yml` — single entry-point playbook
- `roles/package_manager/` — bounded package transaction and recovery logic
- `roles/prereqs/` — kernel, sysctl, swap, and base packages
- `roles/container_runtime/` — containerd 2.x
- `roles/kubernetes_node/` — Kubernetes repository and packages
- `roles/firewall/` — source-restricted firewalld zone
- `roles/hardening/` — SELinux and SSH baseline
- `roles/verification/` — end-state checks
- `scripts/reconcile-known-host.sh` — Terraform replacement host-key reconciliation
- `procedures/SYSTEM-INIT-PROCEDURE.md` — operating procedure
