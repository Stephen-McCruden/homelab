# Homelab Infrastructure Platform

This repository contains the Infrastructure as Code, configuration management, Kubernetes bootstrap, GitOps, and operational documentation used to build and operate a three-node Proxmox-based Kubernetes home lab.

The central design goal is **reproducibility**: the virtual infrastructure, operating-system baseline, Kubernetes cluster, and GitOps control plane should be provisioned, validated, destroyed, and rebuilt from code without relying on undocumented manual configuration.

> **Current status:** Terraform provisions the Fedora Cloud virtual machines; Ansible converges and validates the node baseline; kubeadm initializes the control plane and joins both workers; Cilium provides cluster networking; and Flux continuously reconciles the repository. All three Ansible stages have demonstrated second-run idempotency with `changed=0`.

## Scope

This repository automates the layers above an already functioning infrastructure foundation.

It **does include**:

- Proxmox VM provisioning with Terraform
- Fedora Cloud and cloud-init configuration
- Kubernetes node preparation and hardening
- kubeadm control-plane initialization and worker joining
- Cilium installation and validation
- Flux GitOps bootstrap and reconciliation validation
- GitOps repository structure for platform services and applications
- Operational procedures and safe configuration templates

It **does not include complete installation guides** for:

- Installing Proxmox VE
- Creating the physical Proxmox cluster
- Designing switching, VLANs, routing, DNS, or firewalling
- Installing or administering Tailscale
- Configuring HCP Terraform accounts from first principles
- General Linux workstation administration

Those systems must already be functional before following the deployment procedures. The [environment setup guide](docs/ENVIRONMENT-SETUP.md) documents the required state and the integration points used by this repository.

## Architecture

```text
Operator workstation
├── Terraform CLI
├── Ansible controller
├── Git and SSH
└── Administrative kubeconfig
          |
          v
Three-node Proxmox VE cluster
├── pve1 -> k8s-worker-01  192.168.0.50
├── pve2 -> k8s-worker-02  192.168.0.51
└── pve3 -> k8s-master-01  192.168.0.52
          |
          v
Kubernetes
├── kubeadm
├── containerd
├── Cilium
└── Flux
          |
          v
Git-managed platform and applications
```

The current Kubernetes topology uses one control-plane node and two worker nodes. This is a resilient workload topology, but it is **not a highly available Kubernetes control plane** because the API server and etcd run on one control-plane VM.

## Deployment Lifecycle

### Stage 0 — Infrastructure

```bash
cd terraform
terraform init
terraform plan
terraform apply
```

Terraform downloads the Fedora Cloud image to the required Proxmox nodes and creates the three virtual machines.

### Stage 1 — Node baseline

```bash
cd ../ansible
ansible-playbook playbooks/system-init.yml
```

This stage prepares Fedora, controls DNF5 transactions, installs Kubernetes tooling and containerd, configures kernel prerequisites, applies SSH and firewall hardening, and verifies the resulting state.

### Stage 2 — Kubernetes cluster

```bash
ansible-playbook playbooks/cluster-bootstrap.yml
```

This stage initializes kubeadm only when required, joins workers only when required, installs Cilium, and validates node, API, CoreDNS, and `kube-system` health.

### Stage 3 — GitOps platform

```bash
ansible-playbook playbooks/platform-bootstrap.yml
```

This stage installs a pinned Flux CLI, performs the one-time GitHub bootstrap when required, validates the SSH deploy-key Secret, and waits for the complete GitOps dependency chain.

### Stage 4 — Backup and recovery

```bash
ansible-playbook playbooks/backup-bootstrap.yml
```

This stage is planned. It will connect a replacement cluster to backup storage, inject recovery credentials safely, restore persistent state when appropriate, and validate backup health.

## Current Operational Guarantees

- Terraform variables containing credentials are excluded from Git.
- Package GPG verification remains enabled.
- DNF5 transactions are serialized and protected from automatic metadata-job races.
- Swap and zram are disabled for Kubernetes.
- containerd uses systemd cgroups.
- kubeadm initialization and worker joining are state-aware.
- Cilium and cluster health use Kubernetes-native readiness checks.
- Flux validates its Git source, SSH authentication material, controllers, branch, and all managed Kustomizations.
- Healthy second runs of all three current Ansible stages report `changed=0`.
- Administrative kubeconfig and private SSH keys remain outside the repository.

## Repository Layout

```text
.
├── README.md
├── docs/
│   ├── ENVIRONMENT-SETUP.md
│   ├── DEPLOYMENT-WORKFLOW.md
│   └── CONFIGURATION-AND-SECRETS.md
├── terraform/
│   ├── README.md
│   ├── terraform.tfvars.example
│   ├── procedures/
│   │   └── TERRAFORM-PROVISIONING-PROCEDURE.md
│   └── *.tf
├── ansible/
│   ├── README.md
│   ├── inventory/
│   │   ├── hosts.yml
│   │   ├── hosts.yml.example
│   │   └── group_vars/
│   │       ├── all.yml
│   │       └── all.yml.example
│   ├── playbooks/
│   ├── roles/
│   └── procedures/
│       ├── SYSTEM-INIT-PROCEDURE.md
│       ├── CLUSTER-BOOTSTRAP-PROCEDURE.md
│       ├── PLATFORM-BOOTSTRAP-PROCEDURE.md
│       └── FULL-REBUILD-PROCEDURE.md
├── clusters/
│   └── homelab/
└── kubernetes/
    ├── infrastructure/
    └── applications/
```

## First-Time Deployment

Start with:

1. [Environment setup](docs/ENVIRONMENT-SETUP.md)
2. [Configuration and secrets](docs/CONFIGURATION-AND-SECRETS.md)
3. [Terraform provisioning](terraform/procedures/TERRAFORM-PROVISIONING-PROCEDURE.md)
4. [System initialization](ansible/procedures/SYSTEM-INIT-PROCEDURE.md)
5. [Cluster bootstrap](ansible/procedures/CLUSTER-BOOTSTRAP-PROCEDURE.md)
6. [Platform bootstrap](ansible/procedures/PLATFORM-BOOTSTRAP-PROCEDURE.md)

## Full Rebuild Objective

The target disaster-recovery workflow is:

```text
terraform apply
    ↓
system-init.yml
    ↓
cluster-bootstrap.yml
    ↓
platform-bootstrap.yml
    ↓
Flux reconstructs declarative platform state from Git
    ↓
backup-bootstrap.yml restores secrets and persistent application data
```

Git preserves desired configuration. External backups must preserve database contents, uploads, persistent-volume data, and other state that cannot be reconstructed from manifests alone.

## Security Note

SELinux remains enabled but is currently configured in permissive mode on Kubernetes nodes because enforcement blocked kubeadm-managed static Pods from required Fedora paths during testing. AVC auditing remains available. This is a documented compatibility decision, not equivalent protection to enforcing mode.

## Roadmap

### Operational

- Terraform provisioning on Proxmox
- HCP Terraform remote state
- Fedora node baseline
- containerd and Kubernetes packages
- kubeadm control-plane bootstrap
- Idempotent worker joining
- Cilium networking
- Complete cluster-health validation
- Flux GitOps bootstrap
- Ordered infrastructure and application reconciliation

### Next

1. Metrics Server
2. cert-manager
3. Traefik
4. Longhorn
5. Prometheus
6. Grafana
7. Loki
8. Backup and disaster-recovery foundation
9. Restore testing
10. Stateful applications

Minecraft is intentionally outside this Kubernetes platform and runs as a Docker workload on a separate server.

## Documentation Philosophy

The repository documents not only successful configuration but also boundaries, assumptions, validation, security tradeoffs, and recovery procedures.
