# Homelab Infrastructure Platform

This repository contains the infrastructure-as-code, configuration-management, Kubernetes bootstrap, and operational documentation used to build and operate my Proxmox-based home lab.

The central design goal is reproducibility: the environment should be provisioned, configured, validated, destroyed, and rebuilt from code without relying on undocumented manual changes.

Terraform provisions the virtual infrastructure. Ansible prepares and hardens the Fedora nodes, initializes the Kubernetes control plane, and retrieves the administrative kubeconfig. Kubernetes and Flux will manage platform services and application workloads as the project progresses.

> **Current status:** Terraform VM provisioning, the Ansible operating-system baseline, second-run idempotency, and automated `kubeadm` control-plane initialization are operational. Worker joining, Cilium deployment, full cluster-health verification, Flux GitOps bootstrap, and disaster-recovery automation are the next implementation phases.

---

## Project Goals

- Rebuild the environment from code after a full destroy, host replacement, or service failure.
- Separate infrastructure provisioning, operating-system configuration, cluster bootstrap, and application delivery.
- Make playbooks safe to run repeatedly without introducing unintended changes.
- Validate the resulting state automatically instead of relying only on successful command completion.
- Retain package-signature verification and apply practical security controls appropriate for the platform.
- Document architecture decisions, operating procedures, failures, incident findings, and recovery tests.
- Practice production-style SRE, DevOps, platform-engineering, and infrastructure-operations workflows.

---

## Architecture

The platform currently uses three Proxmox VE hosts and three Fedora Cloud virtual machines for Kubernetes.

```text
Developer workstation
        |
        | Terraform / Ansible / Git
        v
Proxmox VE cluster
        |
        +-- k8s-master-01   192.168.0.52
        +-- k8s-worker-01   192.168.0.50
        +-- k8s-worker-02   192.168.0.51
```

Remote administration is available through Tailscale. A Proxmox node advertises the home-lab subnet, allowing the workstation to reach the Kubernetes VMs securely from outside the local network.

---

## Deployment Lifecycle

### 1. Infrastructure provisioning — Terraform

Terraform communicates with the Proxmox VE API and manages:

- Fedora Cloud image downloads
- Virtual-machine creation
- CPU, memory, disk, and network configuration
- Static IPv4 assignments
- Cloud-init user configuration
- SSH public-key injection
- Placement across Proxmox nodes
- Destruction and reprovisioning
- Remote Terraform state

Terraform creates infrastructure. It does not perform operating-system hardening or initialize Kubernetes.

### 2. Node preparation and hardening — Ansible

The system initialization playbook is:

```bash
ansible-playbook playbooks/system-init.yml
```

It performs:

- Controller-side SSH host-key reconciliation for recreated VMs
- Controller, operating-system, inventory, variable, and sudo validation
- DNF5 transaction control and package-cache recovery
- Automatic DNF metadata-job suppression
- Kubernetes prerequisite installation
- Kernel-module and sysctl configuration
- Swap and zram disabling
- containerd 2.x installation and managed configuration
- `SystemdCgroup = true` validation
- Kubernetes repository and package installation
- `kubelet`, `kubeadm`, `kubectl`, `runc`, and `crictl` verification
- Source-restricted firewalld configuration
- SELinux permissive mode for the current Fedora/Kubernetes compatibility requirement
- SSH key-only access and daemon hardening
- End-of-run service and configuration validation

The playbook is designed to converge from a fresh Terraform deployment and report no changes on a second run.

### 3. Kubernetes control-plane bootstrap — Ansible

The cluster bootstrap playbook is:

```bash
ansible-playbook playbooks/cluster-bootstrap.yml
```

It currently performs:

- kubeadm version discovery
- kubeadm configuration rendering
- kubeadm configuration validation
- Control-plane image pre-pull
- Idempotent `kubeadm init`
- API-server port and readiness checks
- Control-plane node registration verification
- Administrative kubeconfig installation on the control-plane node
- Secure kubeconfig retrieval to the Ansible controller

The bootstrap role checks for partial or inconsistent control-plane state before attempting initialization.

### 4. Cluster completion — In progress

The next Ansible phase will automate:

- Cilium CNI deployment
- Join-token generation
- Worker `JoinConfiguration` rendering
- Worker-node joining
- CoreDNS and network readiness
- All-node health verification
- Repeated-run validation

### 5. GitOps and platform services — Planned

Flux will become responsible for continuously reconciling Kubernetes platform and application configuration from Git.

Planned GitOps-managed components include:

- Cilium lifecycle configuration
- Traefik ingress
- cert-manager
- Longhorn distributed storage
- Prometheus and Grafana
- Loki and centralized logging
- Alerting and service-level objectives
- Ghost and supporting stateful services
- Additional self-hosted workloads
- Backup and disaster-recovery tooling

Capabilities remain listed as planned until their code, procedures, and validation evidence are committed.

---

## Repository Structure

```text
.
├── terraform/
│   ├── README.md
│   ├── main.tf
│   ├── variables.tf
│   ├── providers.tf
│   ├── outputs.tf
│   └── terraform.tfvars        # local and ignored
│
├── ansible/
│   ├── README.md
│   ├── ansible.cfg
│   ├── inventory/
│   │   ├── hosts.yml
│   │   └── group_vars/
│   ├── playbooks/
│   │   ├── system-init.yml
│   │   └── cluster-bootstrap.yml
│   ├── roles/
│   │   ├── package_manager/
│   │   ├── prereqs/
│   │   ├── container_runtime/
│   │   ├── kubernetes_node/
│   │   ├── firewall/
│   │   ├── hardening/
│   │   ├── verification/
│   │   ├── kubeadm_config/
│   │   ├── control_plane/
│   │   └── kubeconfig/
│   ├── scripts/
│   ├── procedures/
│   └── docs/
│
├── kubernetes/
│   ├── platform/
│   └── applications/
│
├── docs/
│   ├── architecture/
│   ├── decisions/
│   ├── incidents/
│   └── postmortems/
│
├── .gitignore
└── README.md
```

The tree will evolve as worker joining, Cilium, Flux, observability, storage, applications, and recovery automation are added.

---

## Standard Workflow

Run Terraform and Ansible as the normal workstation user. Do not run Ansible through local `sudo`.

### Provision or rebuild the virtual machines

```bash
cd terraform
terraform init
terraform plan
terraform apply
```

### Prepare and validate the nodes

```bash
cd ../ansible
ansible-playbook playbooks/system-init.yml
```

### Initialize the Kubernetes control plane

```bash
ansible-playbook playbooks/cluster-bootstrap.yml
```

No manual `kubeadm init` command is required.

### Verify repeatability

Run both playbooks again:

```bash
ansible-playbook playbooks/system-init.yml
ansible-playbook playbooks/cluster-bootstrap.yml
```

The node-baseline playbook should report no changes. The cluster-bootstrap playbook must not rerun `kubeadm init` against an initialized control plane.

### Full rebuild test

```bash
cd ../terraform
terraform destroy
terraform apply

cd ../ansible
ansible-playbook playbooks/system-init.yml
ansible-playbook playbooks/cluster-bootstrap.yml
```

The controller-side SSH reconciliation step removes stale host keys when replacement VMs reuse the same names and addresses.

---

## Security Baseline

The current baseline includes:

- SELinux enabled in permissive mode
- SELinux AVC auditing retained
- SSH public-key authentication
- Root SSH login disabled
- Password authentication disabled
- Keyboard-interactive authentication disabled
- Empty SSH passwords disabled
- Firewalld enabled
- Kubernetes ports restricted to a dedicated source-based zone
- NodePort access disabled unless explicitly enabled
- Package GPG verification retained
- Remote passwordless sudo validated before configuration
- Administrative key presence verified before password authentication is disabled
- Sensitive Terraform variable files excluded from Git
- Administrative Kubernetes kubeconfig stored outside the repository

SELinux permissive mode is a documented compatibility decision for the current Fedora 44, containerd, and kubeadm implementation. It remains enabled and records policy denials. Re-enabling enforcement remains a future hardening objective after the policy incompatibility is resolved and tested.

---

## Reliability and Testing Strategy

The repository is tested against the real Proxmox environment rather than relying only on syntax validation.

Current and planned validation includes:

- Terraform formatting and validation
- Terraform plan review
- Ansible syntax checks
- Ansible linting
- Successful first-run convergence
- Successful second-run idempotency
- Full Terraform destroy-and-rebuild testing
- Service and configuration assertions
- kubeadm configuration validation
- Kubernetes API readiness checks
- Control-plane state consistency checks
- Failure injection
- Backup restoration testing
- Recovery-time and recovery-point measurement
- Incident reports and postmortems

GitHub Actions and role-level automated testing will complement, not replace, integration testing against Proxmox, systemd, SELinux, firewalld, DNF5, containerd, and kubeadm.

---

## Roadmap

### Completed or operational

- Proxmox VM provisioning with Terraform
- Fedora Cloud VM deployment
- Static addressing and SSH-key injection
- Tailscale-based remote administration
- Remote Terraform state
- Modular Ansible roles
- DNF5 transaction and cache recovery
- Kubernetes node prerequisites
- containerd 2.x configuration
- Kubernetes package installation
- `runc` and `crictl` installation
- Source-restricted firewalld baseline
- SSH hardening
- SELinux compatibility configuration
- Automated node verification
- Second-run node-baseline idempotency
- kubeadm configuration generation and validation
- Automated control-plane initialization
- Kubernetes API readiness verification
- Administrative kubeconfig retrieval

### In progress

- Cilium deployment
- Worker-node joining
- Full cluster-health verification
- CI validation
- Expanded procedures and architecture records

### Planned

- Flux GitOps bootstrap
- Traefik ingress
- cert-manager
- Longhorn storage
- Prometheus, Grafana, Loki, and alerting
- SLO and SLA exercises
- Backup and restore automation
- Disaster-recovery testing
- Controlled failure simulations
- Kubernetes upgrade automation
- Complete platform and application restoration from code and backups

---

## Documentation Philosophy

This repository is intended to show both the resulting platform and the engineering process behind it. Architecture decisions, procedures, incident findings, postmortems, validation results, and measured recovery outcomes will be committed alongside the code.

The objective is not to represent a home lab as identical to a commercial production platform. The objective is to apply production-style disciplines—repeatability, observability, security, testing, documentation, controlled change, and recovery—to a real multi-node environment.
