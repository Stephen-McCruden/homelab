# Homelab Terraform

This directory contains the Terraform configuration used to provision Fedora Cloud virtual machines for the Kubernetes home lab on Proxmox VE.

Terraform is responsible only for the infrastructure lifecycle. Operating-system configuration, hardening, containerd setup, Kubernetes installation, and cluster bootstrap are handled by Ansible.

---

## Provisioned Topology

```text
Proxmox VE cluster
├── k8s-worker-01   192.168.0.50
├── k8s-worker-02   192.168.0.51
└── k8s-master-01   192.168.0.52
```

The VMs are distributed across the available Proxmox nodes and receive their configuration through cloud-init.

---

## Terraform Responsibilities

The configuration currently manages:

- Fedora Cloud image acquisition
- VM creation on Proxmox VE
- VM names and placement
- CPU and memory allocation
- Disk configuration
- Network-interface configuration
- Static IPv4 addressing
- Default gateway and DNS settings
- Cloud-init user creation
- SSH public-key injection
- VM lifecycle changes
- Remote Terraform state

Terraform does not:

- Install operating-system packages
- Configure containerd
- Harden SSH
- Configure firewalld
- Run `kubeadm`
- Join Kubernetes nodes
- Deploy applications

Those responsibilities belong to Ansible and, later, Flux.

---

## Files

The exact layout may evolve, but this directory generally contains:

```text
terraform/
├── README.md
├── main.tf
├── providers.tf
├── variables.tf
├── outputs.tf
├── terraform.tfvars
└── .terraform.lock.hcl
```

### Tracked files

The following should normally be committed:

```text
*.tf
.terraform.lock.hcl
README.md
```

### Local or sensitive files

The following must not be committed:

```text
terraform.tfvars
*.auto.tfvars
*.tfstate
*.tfstate.*
.terraform/
crash.log
```

`terraform.tfvars` may contain Proxmox credentials, SSH public keys, host-specific values, or other environment-specific data. Keep it in the local working directory and transfer it securely between authorized controller systems when necessary.

---

## Prerequisites

The controller requires:

- Terraform
- Network access to the Proxmox VE API
- Valid Proxmox API credentials
- Permission to create and destroy the required resources
- A valid SSH public key for cloud-init injection
- Access to the configured remote-state backend

Verify Terraform:

```bash
terraform version
```

---

## Initialization

From the `terraform/` directory:

```bash
terraform init
```

This initializes the backend, downloads the required providers, and creates or updates the local `.terraform/` working directory.

Re-run initialization when:

- The backend configuration changes
- Provider requirements change
- The working directory is newly cloned
- Terraform explicitly requests reinitialization

---

## Formatting and Validation

Before planning:

```bash
terraform fmt -recursive
terraform validate
```

Formatting should complete without leaving unexpected changes, and validation must pass before applying infrastructure.

---

## Planning

Create and review an execution plan:

```bash
terraform plan
```

Terraform may also write the plan to a file:

```bash
terraform plan -out=tfplan
terraform show tfplan
```

Do not commit the plan file. It may include environment-specific or sensitive values.

Review every destructive or replacement action before proceeding.

---

## Applying

Provision or update the infrastructure:

```bash
terraform apply
```

For a previously saved plan:

```bash
terraform apply tfplan
```

After the VMs are available, move to the Ansible directory:

```bash
cd ../ansible
ansible-playbook playbooks/system-init.yml
ansible-playbook playbooks/cluster-bootstrap.yml
```

Terraform should not invoke Ansible implicitly unless that integration is deliberately designed and documented later.

---

## Destroying and Rebuilding

Destroy all resources managed by the current state:

```bash
terraform destroy
```

Then rebuild:

```bash
terraform apply
```

A complete platform rebuild currently continues with:

```bash
cd ../ansible
ansible-playbook playbooks/system-init.yml
ansible-playbook playbooks/cluster-bootstrap.yml
```

The Ansible system initialization playbook reconciles stale SSH host keys caused by replacement VMs reusing the same addresses.

`terraform destroy` is destructive. Review the plan and confirm that no required persistent data exists only inside the resources being removed.

---

## State Management

Terraform state is authoritative for the resources managed by this configuration.

Important rules:

- Do not edit state files manually.
- Do not commit local state to Git.
- Do not run conflicting Terraform operations from multiple controllers.
- Confirm that remote-state locking is functioning before concurrent work.
- Back up or protect the remote backend according to its service capabilities.
- Use `terraform state` commands only when the resource and state consequences are understood.

Useful inspection commands:

```bash
terraform state list
terraform show
terraform output
```

---

## Variables and Secrets

Define variable declarations in `variables.tf`.

Supply environment-specific values through the ignored `terraform.tfvars` file or approved environment variables.

Example structure only:

```hcl
proxmox_api_url = "https://proxmox.example:8006/api2/json"
proxmox_node    = "pve1"
ssh_public_key = "ssh-rsa ..."

# Keep credentials and tokens out of tracked files.
```

Never place real API tokens, private keys, passwords, or sensitive state values in the README or committed `.tf` files.

Only the SSH **public** key belongs in Terraform input. The private key remains on the authorized Ansible controller.

---

## SSH Key Changes

When moving the repository to another workstation:

1. Generate or select the workstation SSH key.
2. Add the public key to the ignored `terraform.tfvars`.
3. Rebuild or update the VMs so cloud-init installs the key.
4. Ensure the Ansible inventory references the matching private key.
5. Run `system-init.yml`, which reconciles stale host keys before connecting.

Never copy a private key into Terraform configuration.

---

## Recommended Command Sequence

For a new clone or controller:

```bash
cd terraform
terraform init
terraform fmt -recursive
terraform validate
terraform plan
terraform apply
```

For normal reviewed changes:

```bash
cd terraform
terraform fmt -recursive
terraform validate
terraform plan
terraform apply
```

For a full rebuild test:

```bash
cd terraform
terraform destroy
terraform apply

cd ../ansible
ansible-playbook playbooks/system-init.yml
ansible-playbook playbooks/cluster-bootstrap.yml
```

---

## Safety and Review Checklist

Before `terraform apply` or `terraform destroy`:

- Confirm the active backend and workspace.
- Review the full plan.
- Verify the target Proxmox nodes.
- Confirm VM names, addresses, and storage targets.
- Check for unexpected replacements.
- Confirm the correct SSH public key is configured.
- Verify required application data is backed up before destruction.
- Ensure no other Terraform operation is running.

---

## Next Terraform Improvements

Planned or potential improvements include:

- Reusable modules for VM classes
- Stronger variable validation
- Additional outputs for Ansible inventory generation
- Automated inventory synchronization
- VLAN-aware networking
- Additional storage configuration
- CI checks for formatting and validation
- Policy checks for destructive plans
