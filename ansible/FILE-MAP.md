# Ansible File Map

## Controller

| Path | Purpose |
|---|---|
| `ansible.cfg` | Inventory, role path, SSH, and privilege-escalation defaults |
| `inventory/hosts.yml` | Reference control-plane and worker topology |
| `inventory/group_vars/all.yml` | Shared reference-environment variables |
| `inventory/*.example` | Reproducer templates |
| `platform-bootstrap.env.example` | Environment-variable names only; never store a real token |
| `scripts/reconcile-known-host.sh` | Reconcile ephemeral VM SSH host keys |
| `../scripts/ansible-yubikey` | Run playbooks with a FIDO2 identity and predictable prompts |

## Playbooks

| Path | Purpose |
|---|---|
| `playbooks/system-init.yml` | Fedora baseline and hardening |
| `playbooks/cluster-bootstrap.yml` | kubeadm, worker joins, kubelet TLS, Cilium, and cluster validation |
| `playbooks/platform-bootstrap.yml` | SOPS bootstrap Secret, Flux bootstrap, and GitOps validation |

## Node Baseline Roles

| Role | Purpose |
|---|---|
| `package_manager` | Serialize DNF5 operations and perform bounded recovery |
| `prereqs` | Packages, kernel modules, sysctls, swap, and zram |
| `longhorn_prereqs` | iSCSI/NFS packages, `iscsi_tcp`, and the iSCSI service |
| `container_runtime` | containerd 2.x with systemd cgroups |
| `kubernetes_node` | Kubernetes repository and packages |
| `firewall` | Source- and port-restricted firewalld configuration |
| `hardening` | SSH and SELinux compatibility state |
| `verification` | Baseline end-state assertions |

## Kubernetes Bootstrap Roles

| Role | Purpose |
|---|---|
| `kubeadm_config` | Render and validate kubeadm configuration |
| `control_plane` | Initialize or verify the control plane |
| `kubeconfig` | Install node-local config and retrieve the controller copy |
| `cilium_node` | Node prerequisites for Cilium |
| `worker_join` | Detect and join only uninitialized workers |
| `kubelet_serving_certificates` | Persist `serverTLSBootstrap`, reconcile every kubelet, and verify TCP `10250` |
| `cilium` | Install the pinned Cilium release and validate it |
| `cluster_verification` | Assert nodes, API, CoreDNS, Cilium, and system workload health |

## Platform Role

| Role | Purpose |
|---|---|
| `flux_bootstrap` | Install Flux CLI, provision `sops-age`, bootstrap GitHub, and wait for its six configured core Kustomizations |

## Procedures

| Path | Purpose |
|---|---|
| `procedures/SYSTEM-INIT-PROCEDURE.md` | Fedora stage runbook |
| `procedures/CLUSTER-BOOTSTRAP-PROCEDURE.md` | Kubernetes stage runbook |
| `procedures/PLATFORM-BOOTSTRAP-PROCEDURE.md` | Flux stage runbook |
| `procedures/FULL-REBUILD-PROCEDURE.md` | Canonical destruction-to-acceptance runbook |

Files ending in `.backup` are historical working residue and are not loaded by
Ansible. Remove them in a separate repository-cleanup change after confirming
that Git history contains the desired versions.
