# Ansible File Map

## Controller Configuration

- `ansible.cfg` - Ansible controller defaults.
- `inventory/hosts.yml` - Local inventory with real node values.
- `inventory/hosts.yml.example` - Safe inventory template.
- `inventory/group_vars/all.yml` - Local shared variables.
- `inventory/group_vars/all.yml.example` - Safe shared-variable template.
- `platform-bootstrap.env.example` - Documentation-only environment variable template. It must not contain a real token.

## Playbooks

- `playbooks/system-init.yml` - Fedora and Kubernetes node baseline.
- `playbooks/cluster-bootstrap.yml` - kubeadm, worker join, Cilium, and cluster verification.
- `playbooks/platform-bootstrap.yml` - SOPS Secret creation, Flux bootstrap, and reconciliation verification.

## Roles

- `roles/package_manager/` - Serialized DNF5 transactions and bounded recovery.
- `roles/prereqs/` - Kernel modules, sysctls, swap, zram, and prerequisites.
- `roles/container_runtime/` - containerd 2.x configuration.
- `roles/kubernetes_node/` - Kubernetes repository and packages.
- `roles/firewall/` - Source-restricted firewalld configuration.
- `roles/hardening/` - SSH and SELinux baseline.
- `roles/verification/` - Node baseline end-state checks.
- `roles/kubeadm_config/` - kubeadm configuration rendering.
- `roles/control_plane/` - Control-plane initialization and API readiness.
- `roles/kubeconfig/` - Administrative kubeconfig retrieval.
- `roles/worker_join/` - State-aware worker joining.
- `roles/cilium_node/` - Node-level Cilium prerequisites.
- `roles/cilium/` - Cilium installation and validation.
- `roles/cluster_verification/` - Kubernetes cluster end-state checks.
- `roles/flux_bootstrap/` - Flux CLI installation, SOPS age Secret automation, GitHub bootstrap, and GitOps validation.

## Procedures

- `procedures/SYSTEM-INIT-PROCEDURE.md` - Node baseline operating procedure.
- `procedures/CLUSTER-BOOTSTRAP-PROCEDURE.md` - Kubernetes bootstrap procedure.
- `procedures/PLATFORM-BOOTSTRAP-PROCEDURE.md` - Flux, token, and SOPS procedure.
- `procedures/FULL-REBUILD-PROCEDURE.md` - End-to-end replacement procedure.

## Repository-Level Scripts Used by Ansible

- `../scripts/reconcile-known-host.sh` - Reconciles SSH host keys after Terraform replaces VMs.
- `../scripts/ansible-yubikey` - Runs Ansible with a FIDO2/YubiKey-backed SSH identity.
