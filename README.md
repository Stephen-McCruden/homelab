# homelab

This repository houses the complete, ground-up automation engine for a high-availability bare-metal infrastructure platform hosted on local Proxmox VE hardware. By treating the home lab as an enterprise production environment, this mono-repo eliminates manual configuration, enforces 100% declarative state management, and implements a strict GitOps deployment workflow.

The platform is engineered to completely decouple infrastructure provisioning, operating system configuration, and application state, ensuring the entire multi-node environment can be destroyed and cleanly redeployed via code with a single pipeline execution.

---

##  Core Architecture & Lifecycle Stages

The deployment lifecycle is divided into three distinct automated layers:

### Phase 1: Infrastructure Provisioning (Terraform)
* **Target:** Proxmox VE API
* **Execution:** Dynamically provisions identical, optimized Linux kernel virtual machines (VMs) from customized cloud-init base images.
* **State Management:** Manages virtual hardware allocations, CPU/RAM topologies, private network bridges, and static IP assignments.

### Phase 2: Configuration Management & Hardening (Ansible)
* **OS Hardening:** Implements baseline security controls, SSH key enforcement, and local firewalls.
* **Kernel Prerequisites:** Declaratively injects low-level storage hooks (`open-iscsi`, `nfs-common`) across all worker nodes.
* **Cluster Bootstrapping:** Automates control plane initialization and secures worker node provisioning via `kubeadm`.

### Phase 3: Cloud-Native GitOps Layer (Kubernetes Applications)
* **Ingress & Routing:** Traefik Edge Proxy managing automated SSL/TLS termination and round-robin load-balancing.
* **Distributed Storage:** Longhorn CSI orchestrating highly available, synchronous block-layer data replication over the local LAN with automated NAS backup routines.
* **Observability Pipeline:** Full-stack Prometheus time-series engines coupled with Grafana visualization dashboards monitoring cluster resource constraints.
* **Application Workloads:** Horizontally scaled, stateless frontend deployments isolated from stateful backend datastores using Kubernetes Pod Anti-Affinity rules.

---

##  Repository Directory Structure

This mono-repo uses a clean, modular design to separate provisioning code from runtime configuration states:

```text
├── terraform/                # Phase 1: Infrastructure Provisioning
│   ├── main.tf               # Core Proxmox VM resource declarations
│   ├── variables.tf          # Hardware and networking variable schemas
│   ├── providers.tf          # Proxmox VE provider configurations
│   └── output.tf             # Generated VM IP addresses and metadata
│
├── ansible/                  # Phase 2: Configuration Management
│   ├── inventory/            # Target host definitions (populated via Terraform)
│   │   └── hosts.yaml
│   ├── playbooks/            # Execution playbooks
│   │   ├── system-init.yaml  # OS hardening and prerequisite installations
│   │   └── k8s-cluster.yaml  # Cluster bootstrapping and node joins
│   └── roles/                # Reusable configuration modules
│
├── kubernetes/               # Phase 3: GitOps Application Manifests
│   ├── core-system/          # Core cluster add-ons (Traefik, Longhorn)
│   └── apps/                 # User-facing services (Ghost, Nginx Frontends)
│
├── .gitignore                # Protection barrier for secrets management
└── README.md                 # System documentation
