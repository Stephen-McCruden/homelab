# Environment Setup and External Prerequisites

This guide describes the infrastructure that must exist before this repository can deploy the Kubernetes platform.

It is an **integration guide**, not a complete Proxmox, networking, Tailscale, GitHub, or HCP Terraform installation tutorial.

## Required Foundation

The reference design assumes:

- Three x86-64 systems running compatible Proxmox VE releases
- A working Proxmox cluster with quorum
- Stable hostnames and management addresses
- Storage for imported cloud images and VM disks
- A Linux bridge available to the Kubernetes VMs
- Functional default-gateway and DNS access
- Time synchronization on all Proxmox hosts
- Sufficient CPU, memory, and storage

Reference placement:

```text
pve1 -> k8s-worker-01
pve2 -> k8s-worker-02
pve3 -> k8s-master-01
```

## Proxmox Cluster Requirements

Before Terraform is used:

```bash
pvecm status
```

should show a healthy cluster and quorum.

Verify that:

- All target nodes are visible in the Proxmox UI
- The import datastore exists on every node used for image downloads
- The VM datastore exists on every node used for VM disks
- The network bridge exists on every node
- The selected VM IDs are unused
- The API endpoint is reachable from the Terraform controller

This repository does not create or repair the Proxmox cluster itself.

## Proxmox API Identity

Create a dedicated automation identity rather than using root credentials directly.

### Recommended UI workflow

1. Open **Datacenter → Permissions → Users**.
2. Create a user such as `terraform-user@pve`.
3. Open **Datacenter → Permissions → API Tokens**.
4. Create a token such as `homelab`.
5. Save the secret immediately.
6. Assign the user or token permission to audit storage and cluster state, download/import images, allocate/configure VMs, power them, and delete managed VMs.

### Permission strategy

For an initial lab deployment, assigning the built-in `PVEAdmin` role at `/` to the dedicated automation identity is the simplest reproducible option. It is broader than least privilege, but safer than using `root@pam` credentials.

After the deployment is stable, replace it with a tested custom role containing only the privileges exercised by the provider and resources.

### Token privilege separation

When privilege separation is enabled, the token needs an ACL assignment appropriate to its operations. Confirm whether the ACL is applied to the user or token and test the real plan/apply/destroy path.

The token ID should resemble:

```text
terraform-user@pve!homelab
```

## Proxmox TLS

The current variables default to:

```hcl
proxmox_insecure = true
```

A stronger deployment should install a trusted certificate and set this to `false`.

## Network Requirements

The VMs require:

- Unique static IPv4 addresses
- A reachable default gateway
- Functional DNS
- TCP 22 from the Ansible controller
- Kubernetes traffic between nodes
- Cilium VXLAN and health traffic between nodes
- Internet access for packages and images

Reference addresses:

```text
k8s-worker-01  192.168.0.50
k8s-worker-02  192.168.0.51
k8s-master-01  192.168.0.52
gateway        192.168.0.1
```

If another subnet is used, update Terraform variables, Ansible inventory, group variables, firewall sources, and external routing.

## Remote Access

The reference environment uses Tailscale subnet routing. This repository does not install or administer Tailscale.

Local-LAN connectivity is sufficient.

## Controller Workstation

Required tools:

- Git
- OpenSSH client
- Terraform
- Python 3
- Ansible Core
- `ansible-lint`
- `yamllint`
- A private SSH key matching a public key injected by Terraform

Checks:

```bash
git --version
ssh -V
terraform version
python3 --version
ansible --version
ansible-lint --version
yamllint --version
```

## HCP Terraform

The current `terraform/main.tf` contains an HCP Terraform `cloud` block. Replace the organization and workspace:

```hcl
terraform {
  cloud {
    organization = "YOUR-HCP-ORGANIZATION"

    workspaces {
      name = "YOUR-HCP-WORKSPACE"
    }
  }
}
```

Authenticate:

```bash
terraform login
```

Use a CLI-driven workspace when plans and applies are initiated locally.

## GitHub and Flux

For the one-time GitHub bootstrap:

- The operator needs a fine-grained PAT
- Restrict it to the homelab repository
- Grant Contents read/write
- Grant enough Administration permission to create the deploy key
- Export it only for the first platform bootstrap
- Remove it afterward

Flux then uses an SSH deploy key.

## Explicit Non-Goals

This guide does not teach Proxmox installation, physical clustering, production network design, Tailscale administration, GitHub account creation, or general Kubernetes administration.
