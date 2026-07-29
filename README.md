# Reproducible Proxmox Kubernetes Homelab

This repository builds a three-node Kubernetes platform on an existing
three-node Proxmox VE cluster. Terraform creates the virtual machines, Ansible
converges Fedora and bootstraps Kubernetes, and Flux continuously reconciles
the platform and its applications from Git.

The project has two documentation goals:

1. A reader can reproduce the design in another lab by replacing the
   environment-specific values.
2. The operator can rebuild this lab from loss without relying on remembered
   commands or undocumented cluster changes.

This is an **operator-assisted reproducible build**. A short-lived GitHub token,
access to external secret stores, and any configured hardware-key touches are
deliberately interactive security controls.

## What the Repository Builds

| Layer | Owner | Result |
|---|---|---|
| Virtual machines | Terraform | Three Fedora Cloud VMs distributed across Proxmox |
| Host operating system | Ansible | Packages, containerd, Kubernetes tools, firewall, SSH hardening, and prerequisites |
| Kubernetes cluster | Ansible and kubeadm | One control plane, two workers, Cilium networking, and secure kubelet serving certificates |
| GitOps control plane | Ansible and Flux | Flux bootstrap, SOPS key provisioning, and reconciliation gates |
| Shared platform | Flux | cert-manager, External Secrets, Longhorn, MetalLB, Prometheus, Alertmanager, Loki, Alloy, Grafana, Tailscale Operator, Traefik, kubelet CSR approver, and Metrics Server |
| Applications | Flux | Public website plus private Homepage, Linkding, Mealie, and FreshRSS services |

The included example topology uses one control-plane VM and two worker VMs
placed across three Proxmox nodes. VM placement, sizing, addresses, DNS,
storage, ingress hostnames, and external-service identifiers are deployment
inputs. Start with [Environment setup](docs/ENVIRONMENT-SETUP.md) before
applying the repository in another lab.

## Current State

The following cold-path fixes are encoded in `main`:

- Fedora Cloud VMs receive explicit DNS servers through cloud-init.
- firewalld permits the required node, Pod-to-API, and Pod-to-kubelet traffic.
- kubeadm enables `serverTLSBootstrap`.
- Ansible reconciles kubelet serving-certificate configuration on every node.
- A dedicated controller validates and approves legitimate kubelet serving
  CSRs before Metrics Server is treated as healthy.
- Flux separates the application-critical dependency path from the node-metrics
  path.
- Longhorn provides a two-replica default StorageClass for persistent
  workloads; application and observability state use `ReadWriteOnce` claims.
- External Secrets restores ACME, FreshRSS, Grafana, Linkding, and Tailscale
  credentials from Azure Key Vault.
- The Tailscale Operator provides private HTTPS access to Homepage, Linkding,
  Mealie, FreshRSS, and Grafana.
- Prometheus, Alertmanager, Grafana, Loki, and Alloy retain operational state
  on Longhorn; Alloy sends Kubernetes logs and events to Loki.
- Traefik uses fixed NodePorts so router rules survive Service recreation.
- Flux image automation promotes immutable preview and production website
  images through Git.

The repository is a **rebuild candidate** until the current commit completes a
clean destroy-to-green test without an undocumented repair. Longhorn provides
in-cluster replication, but off-cluster backup and application-data restore
are not implemented yet.

## Architecture at a Glance

```text
Operator workstation
  ├─ Terraform ───────────────> Proxmox API
  ├─ Ansible over SSH ────────> Fedora VMs
  ├─ SOPS age identity ───────> flux-system/sops-age
  └─ kubectl/Flux CLI ────────> Kubernetes API

Proxmox VE
  └─ Fedora VMs
       └─ kubeadm + containerd + Cilium
            └─ Flux
                 ├─ controllers -> configs -> Tailscale -> applications
                 ├─ kubelet CSR approver -> Metrics Server
                 └─ website image selection -> Git commit
```

The cluster has a single API server and single etcd member. Application
replicas can tolerate a worker failure, but Kubernetes control-plane
availability is not highly available.

See [Architecture](docs/ARCHITECTURE.md) for ownership boundaries, traffic
paths, failure domains, and the complete Flux dependency graph.

## Repository Layout

```text
.
├── terraform/                    Proxmox VM lifecycle
├── ansible/                      Fedora and Kubernetes bootstrap
├── clusters/homelab/             Flux Kustomization dependency graph
├── kubernetes/infrastructure/    Shared controllers and configuration
├── kubernetes/applications/      User-facing workloads
├── scripts/                      Controller-side execution wrappers
└── docs/                         Design and operating documentation
```

## Reproduce or Rebuild

For a new operator:

1. Read [Architecture](docs/ARCHITECTURE.md).
2. Satisfy [Environment setup](docs/ENVIRONMENT-SETUP.md).
3. Adapt [Configuration and secrets](docs/CONFIGURATION-AND-SECRETS.md).
4. Follow the [Deployment workflow](docs/DEPLOYMENT-WORKFLOW.md).

For this lab after deliberate destruction or loss:

1. Start with the
   [full rebuild procedure](ansible/procedures/FULL-REBUILD-PROCEDURE.md).
2. Use the component procedure linked at the failing stage.
3. Diagnose with [Troubleshooting](docs/TROUBLESHOOTING.md).
4. Encode the correction in Terraform, Ansible, Flux, or the documented
   external prerequisite before attempting the next proof.

Do not compensate for an automation failure with an undocumented permanent
manual change.

## Documentation Index

### Understand and reproduce

- [Architecture](docs/ARCHITECTURE.md)
- [Environment setup](docs/ENVIRONMENT-SETUP.md)
- [Configuration and secrets](docs/CONFIGURATION-AND-SECRETS.md)
- [Controller authentication](docs/CONTROLLER-AUTHENTICATION.md)
- [Deployment workflow](docs/DEPLOYMENT-WORKFLOW.md)
- [Ingress, DNS, and TLS](docs/INGRESS-DNS-AND-TLS.md)

### Operate and recover

- [Operations quick reference](docs/OPERATIONS.md)
- [Troubleshooting](docs/TROUBLESHOOTING.md)
- [Storage and backups](docs/STORAGE-AND-BACKUPS.md)
- [Observability](docs/OBSERVABILITY.md)
- [Full rebuild](ansible/procedures/FULL-REBUILD-PROCEDURE.md)

### Extend the platform

- [Website and applications](docs/WEBSITE-AND-APPLICATIONS.md)
- [Terraform reference](terraform/README.md)
- [Ansible reference](ansible/README.md)
- [Ansible file map](ansible/FILE-MAP.md)

## Normal Deployment Stages

From the repository root:

```bash
cd terraform
terraform init
terraform plan
terraform apply

cd ../ansible
../scripts/ansible-yubikey playbooks/system-init.yml
../scripts/ansible-yubikey playbooks/cluster-bootstrap.yml
```

A new Flux installation also requires a short-lived GitHub fine-grained token:

```bash
(
  read -rsp "GitHub fine-grained token: " GITHUB_TOKEN
  printf '\n'
  export GITHUB_TOKEN

  ../scripts/ansible-yubikey playbooks/platform-bootstrap.yml
)
```

Use normal `ansible-playbook` commands instead of the wrapper when using a
file-backed SSH key. The detailed stage gates and validation commands are in
the [deployment workflow](docs/DEPLOYMENT-WORKFLOW.md).

## Definition of Healthy

A completed deployment must satisfy all of the following:

```bash
kubectl get nodes
kubectl get kustomizations --namespace flux-system
kubectl get helmreleases --all-namespaces
kubectl top nodes
kubectl get clusterissuer
kubectl get certificate --all-namespaces
kubectl get volumes.longhorn.io --namespace longhorn-system
kubectl get ingress --all-namespaces
```

Expected outcomes:

- All three nodes are `Ready`.
- Every Flux Kustomization is `Ready=True`.
- Every managed HelmRelease is `Ready=True`.
- Metrics Server reports all nodes.
- Both ACME ClusterIssuers and the wildcard certificate are Ready.
- Longhorn volumes are healthy.
- Public and private HTTPS endpoints validate normally without bypassing TLS.
- A second run of every Ansible playbook has no failed or unreachable hosts.

## Current Limits

- One control-plane node and one etcd member.
- Longhorn currently uses the VM root filesystems; dedicated data disks are not
  provisioned.
- No off-cluster Longhorn backup target or tested persistent-volume restore.
- Router, Proxmox, Cloudflare DNS, Azure Key Vault, HCP Terraform, and the SOPS
  recovery key are external dependencies. Private endpoints additionally
  depend on Tailscale.
- SELinux is enabled in permissive mode as a documented Fedora compatibility
  decision.
- Public applications are unavailable during a complete cluster rebuild.

## Next Milestones

1. Record the current platform baseline and verification evidence.
2. Verify observability data survives Pod deletion and rescheduling.
3. Configure an off-cluster backup target and complete restore tests.
4. Add host journals and private appliance syslog to Alloy.
5. Complete and record a clean rebuild proof with measured recovery time.
6. Add update automation, risk review, and human-approved ChatOps.

The ordered design is maintained in
[Website and applications](docs/WEBSITE-AND-APPLICATIONS.md),
[Storage and backups](docs/STORAGE-AND-BACKUPS.md), and
[Observability](docs/OBSERVABILITY.md).
