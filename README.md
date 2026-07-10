# Homelab Infrastructure Platform

This repository contains the infrastructure-as-code, configuration-management, and Kubernetes resources used to build and operate my Proxmox-based home lab.

The project is designed around a simple goal: the environment should be reproducible, testable, documented, and recoverable without relying on undocumented manual configuration. Terraform provisions the virtual infrastructure, Ansible prepares and hardens the operating systems, and Kubernetes will manage the platform services and application workloads.

> **Current status:** Terraform provisioning and the Ansible system-initialization baseline are operational. Automated Kubernetes control-plane initialization, node joining, GitOps deployment, and disaster-recovery workflows are the next implementation phases.

---

## Project Goals

- Rebuild the environment from code after a full destroy or failure.
- Keep provisioning, operating-system configuration, and application deployment separated.
- Make Ansible roles safe to run repeatedly without creating unintended changes.
- Apply a secure Fedora baseline without disabling SELinux or weakening package verification.
- Validate the resulting state automatically at the end of each playbook run.
- Document architecture decisions, procedures, failures, and recovery testing.
- Use the lab to practice production-style SRE, DevOps, platform-engineering, and infrastructure-operations workflows.

---

## Architecture

The platform currently runs across three Proxmox VE nodes and uses Fedora Cloud virtual machines for the Kubernetes nodes.

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

Remote administration is performed through Tailscale. A Proxmox node advertises the home-lab subnet, allowing the Ansible controller to reach the Kubernetes VMs securely while away from the local network.

---

## Deployment Lifecycle

### 1. Infrastructure Provisioning — Terraform

Terraform communicates with the Proxmox VE API and currently manages:

- Fedora Cloud image downloads
- Virtual-machine creation
- CPU, memory, disk, and network configuration
- Static IPv4 assignments
- Cloud-init user configuration
- SSH public-key injection
- Reprovisioning through `terraform destroy` and `terraform apply`
- Remote Terraform state

Terraform is responsible for creating infrastructure. It does not perform operating-system hardening or Kubernetes configuration.

### 2. System Configuration and Hardening — Ansible

The primary playbook is:

```bash
ansible-playbook playbooks/system-init.yml
```

The playbook currently performs:

- SSH host-key reconciliation for Terraform-recreated VMs
- Fedora and inventory validation
- Passwordless remote-sudo validation
- Resilient DNF5 package installation with cache recovery
- Kubernetes kernel-module configuration
- Required sysctl configuration
- Swap and zram disabling
- containerd installation and systemd-cgroup configuration
- Versioned Kubernetes repository configuration
- `kubelet`, `kubeadm`, and `kubectl` installation
- Firewalld configuration with a source-restricted Kubernetes zone
- SELinux enforcement
- SSH key-only authentication and SSH daemon hardening
- End-of-run verification for services, swap, sysctl, SELinux, SSH, Kubernetes tools, and containerd

The Ansible design is role-based and intended to be idempotent. A second run should complete without reapplying unchanged configuration.

### 3. Kubernetes Bootstrap — In Progress

The next Ansible phase will automate:

- `kubeadm init`
- Control-plane configuration
- Worker join-token generation
- Worker-node joining
- CNI deployment
- Cluster-health validation
- Kubeconfig distribution
- Reset and rebuild procedures
- Upgrade procedures

### 4. GitOps and Platform Services — Planned

The Kubernetes layer will eventually manage:

- Traefik ingress
- TLS and external routing
- Longhorn distributed storage
- Prometheus and Grafana
- Loki and centralized logging
- Alerting and service-level objectives
- Ghost and supporting stateful services
- Additional self-hosted workloads
- Backup and disaster-recovery jobs

These capabilities are documented as planned work and should not be treated as completed until their manifests, procedures, and validation results are committed.

---

## Repository Structure

```text
.
├── terraform/
│   ├── main.tf
│   ├── variables.tf
│   ├── providers.tf
│   ├── outputs.tf
│   └── modules/
│
├── ansible/
│   ├── ansible.cfg
│   ├── inventory/
│   │   ├── hosts.yml
│   │   └── group_vars/
│   │       └── all.yml
│   ├── playbooks/
│   │   └── system-init.yml
│   ├── roles/
│   │   ├── package_manager/
│   │   ├── prereqs/
│   │   ├── container_runtime/
│   │   ├── kubernetes_node/
│   │   ├── firewall/
│   │   ├── hardening/
│   │   └── verification/
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

The exact tree will evolve as the Kubernetes bootstrap, GitOps, observability, and recovery phases are implemented.

---

## Current Workflow

### Provision or rebuild the virtual machines

```bash
cd terraform
terraform plan
terraform apply
```

### Prepare and harden the nodes

Run Ansible as the normal local user, not through `sudo`:

```bash
cd ../ansible
ansible-playbook playbooks/system-init.yml
```

Ansible connects to the VMs using the Terraform-provisioned SSH key and applies privilege escalation only on the remote nodes.

### Test repeatability

Run the same playbook again:

```bash
ansible-playbook playbooks/system-init.yml
```

The goal is for the second run to report no unintended changes and no failures.

### Full rebuild test

```bash
cd ../terraform
terraform destroy
terraform apply

cd ../ansible
ansible-playbook playbooks/system-init.yml
```

The controller-side SSH reconciliation step handles changed host keys when replacement VMs reuse the same addresses.

---

## Security Baseline

The current baseline includes:

- SELinux enforcing
- SSH public-key authentication
- Root SSH login disabled
- Password authentication disabled
- Keyboard-interactive authentication disabled
- Firewalld enabled
- Kubernetes ports opened only in a dedicated source-restricted zone
- NodePort range disabled unless explicitly enabled
- GPG validation retained for package installation
- Remote sudo validated before configuration begins
- Administrative key presence checked before SSH passwords are disabled

Public-zone SSH removal is intentionally controlled by a variable so source-restricted access can be validated before stricter firewall enforcement is enabled.

---

## Reliability and Testing Strategy

This repository is being developed using repeated real-environment tests rather than treating successful syntax validation as sufficient.

Validation goals include:

- Terraform plan review
- Ansible syntax and lint checks
- Successful first-run convergence
- Successful second-run idempotency
- Full destroy-and-rebuild testing
- Service and configuration verification
- Failure injection
- Recovery-time and recovery-point measurements
- Incident reports and postmortems
- Backup restoration tests

Molecule and GitHub Actions are planned or under development for automated syntax, lint, and role-level validation. The Proxmox environment remains the authoritative integration-test platform for systemd, SELinux, firewalld, kernel modules, swap, and VM lifecycle behavior.

---

## Roadmap

### Completed or operational

- Proxmox VM provisioning with Terraform
- Fedora Cloud VM deployment
- Static addressing and SSH-key injection
- Tailscale-based remote administration
- Modular Ansible role structure
- DNF5 package-cache recovery
- Kubernetes node prerequisites
- containerd configuration
- Kubernetes package installation
- Firewalld baseline
- SELinux and SSH hardening
- Automated node verification

### In progress

- Final second-run idempotency cleanup
- Automated Kubernetes bootstrap
- Worker joining
- CNI selection and deployment
- CI validation
- Expanded procedures and architecture records

### Planned

- GitOps delivery
- Traefik ingress
- Longhorn storage
- Prometheus, Grafana, Loki, and alerting
- SLO and SLA exercises
- Backup and restore automation
- Disaster-recovery testing
- Controlled failure simulations
- Kubernetes upgrade automation
- Complete environment rebuild from infrastructure-as-code only

---

## Documentation Philosophy

The repository is intended to show not only the finished configuration but also the engineering process behind it. Architecture decisions, procedures, incident findings, postmortems, and measured recovery results will be committed alongside the code.

The objective is not to claim that a home lab is identical to a commercial production platform. The objective is to apply production-style engineering disciplines—repeatability, observability, security, testing, documentation, and recovery—to a real multi-node environment.
