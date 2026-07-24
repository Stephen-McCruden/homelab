# Homelab Infrastructure Platform

This repository builds and operates a three-node Proxmox-based Kubernetes home lab with Terraform, Ansible, kubeadm, Cilium, Flux, SOPS, and GitOps-managed platform services.

The main goal is reproducibility. A replacement cluster should be built from code without relying on undocumented manual commands.

## Current State

The following stages are operational:

- Terraform provisions three Fedora Cloud virtual machines on Proxmox.
- Ansible configures the Fedora node baseline, containerd, Kubernetes packages, firewall rules, SSH hardening, and cluster prerequisites.
- kubeadm initializes one control-plane node and joins two workers.
- Cilium provides Kubernetes networking.
- Flux bootstraps the cluster from GitHub and reconciles the repository.
- Ansible creates the `flux-system/sops-age` Secret before Flux applies encrypted manifests.
- cert-manager, External Secrets Operator, kubelet CSR approver, Metrics Server, MetalLB, kube-prometheus-stack, and Traefik are GitOps-managed.
- Azure Key Vault supplies runtime secrets through External Secrets Operator.
- cert-manager issues the wildcard certificate used by Traefik.
- Grafana is deployed through Flux.
- Traefik NodePorts are pinned so router port-forward rules do not change after a rebuild.

The current Flux dependency chain is:

```text
flux-system
    -> infrastructure-controllers
    -> infrastructure-configs
    -> applications
```

This ordering is functional. More granular dependency separation can be added later after the full rebuild path is verified.

## Architecture

```text
Operator workstation
├── Terraform CLI
├── Ansible controller
├── Git and OpenSSH
├── SOPS age private key
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
Git-managed controllers, configuration, and applications
```

The cluster has one control-plane node. Workloads can run across three nodes, but the Kubernetes API server and etcd are not highly available.

## Ingress Path

```text
Internet TCP 80
    -> router
    -> 192.168.0.52:32492
    -> Traefik web NodePort

Internet TCP 443
    -> router
    -> 192.168.0.52:30860
    -> Traefik websecure NodePort
```

Traefik also has the MetalLB address `192.168.0.220`. That address is a LoadBalancer virtual IP advertised on the LAN. It is not a Pod IP.

Grafana remains behind Traefik as a normal Kubernetes Service. The router forwards to Traefik, not directly to Grafana.

See [Ingress, DNS, and TLS](docs/INGRESS-DNS-AND-TLS.md).

## Deployment Stages

### Stage 0: Proxmox virtual machines

```bash
cd terraform
terraform init
terraform plan
terraform apply
```

### Stage 1: Fedora and Kubernetes node baseline

```bash
cd ../ansible
ansible-playbook playbooks/system-init.yml
```

YubiKey-backed SSH users can run:

```bash
../scripts/ansible-yubikey playbooks/system-init.yml
```

### Stage 2: Kubernetes cluster

```bash
ansible-playbook playbooks/cluster-bootstrap.yml
```

### Stage 3: Flux and GitOps platform

The first bootstrap of a replacement cluster requires a GitHub fine-grained personal access token. The SOPS age private key must also be available on the Ansible controller.

```bash
read -rsp "GitHub fine-grained token: " GITHUB_TOKEN
printf '\n'
export GITHUB_TOKEN

ansible-playbook playbooks/platform-bootstrap.yml

unset GITHUB_TOKEN
```

With the YubiKey SSH wrapper:

```bash
read -rsp "GitHub fine-grained token: " GITHUB_TOKEN
printf '\n'
export GITHUB_TOKEN

../scripts/ansible-yubikey playbooks/platform-bootstrap.yml

unset GITHUB_TOKEN
```

The token is not required on later healthy runs because Flux uses the SSH deploy key stored in the cluster.

## Repository Layout

```text
.
├── README.md
├── docs/
│   ├── CONFIGURATION-AND-SECRETS.md
│   ├── CONTROLLER-AUTHENTICATION.md
│   ├── DEPLOYMENT-WORKFLOW.md
│   ├── ENVIRONMENT-SETUP.md
│   └── INGRESS-DNS-AND-TLS.md
├── terraform/
│   ├── README.md
│   ├── terraform.tfvars.example
│   └── procedures/
│       └── TERRAFORM-PROVISIONING-PROCEDURE.md
├── ansible/
│   ├── README.md
│   ├── FILE-MAP.md
│   ├── platform-bootstrap.env.example
│   ├── inventory/
│   ├── playbooks/
│   ├── roles/
│   └── procedures/
│       ├── SYSTEM-INIT-PROCEDURE.md
│       ├── CLUSTER-BOOTSTRAP-PROCEDURE.md
│       ├── PLATFORM-BOOTSTRAP-PROCEDURE.md
│       └── FULL-REBUILD-PROCEDURE.md
├── clusters/
│   └── homelab/
├── kubernetes/
│   ├── infrastructure/
│   └── applications/
└── scripts/
    ├── ansible-yubikey
    └── reconcile-known-host.sh
```

## Start Here

1. [Environment setup](docs/ENVIRONMENT-SETUP.md)
2. [Controller authentication](docs/CONTROLLER-AUTHENTICATION.md)
3. [Configuration and secrets](docs/CONFIGURATION-AND-SECRETS.md)
4. [Deployment workflow](docs/DEPLOYMENT-WORKFLOW.md)
5. [Terraform provisioning](terraform/procedures/TERRAFORM-PROVISIONING-PROCEDURE.md)
6. [System initialization](ansible/procedures/SYSTEM-INIT-PROCEDURE.md)
7. [Cluster bootstrap](ansible/procedures/CLUSTER-BOOTSTRAP-PROCEDURE.md)
8. [Platform bootstrap](ansible/procedures/PLATFORM-BOOTSTRAP-PROCEDURE.md)
9. [Full rebuild](ansible/procedures/FULL-REBUILD-PROCEDURE.md)

## Current Limits

- The Kubernetes control plane is not highly available.
- Persistent-volume, database, and application-data restoration is not automated yet.
- Router and public DNS configuration remain external to Kubernetes.
- The current Flux dependency graph is intentionally broad and will be refined after a successful unattended rebuild.
- SELinux remains enabled in permissive mode on the Kubernetes nodes as a documented Fedora compatibility decision.

## Next Work

1. Run and validate a complete unattended rebuild.
2. Fix any remaining node-level Metrics Server issue.
3. Refine Flux dependencies and readiness gates.
4. Add persistent storage and backup restoration.
5. Add Loki and centralized log retention.
6. Update recovery testing, RTO, and RPO documentation.
