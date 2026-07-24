# Homelab Terraform

This directory provisions three Fedora Cloud virtual machines across an existing Proxmox VE cluster.

Terraform owns the VM infrastructure. Ansible owns Fedora and Kubernetes configuration. Flux owns Kubernetes platform and application resources.

## Requirements

- Healthy Proxmox VE cluster with quorum.
- Existing storage IDs and Linux bridges.
- Dedicated Proxmox API identity and token.
- Controller access to the Proxmox API.
- Configured HCP Terraform organization and workspace, or an intentionally different backend.
- Local `terraform.tfvars`.
- SSH public key matching the Ansible controller's private key or YubiKey-backed SSH key.

See:

- [Environment setup](../docs/ENVIRONMENT-SETUP.md)
- [Configuration and secrets](../docs/CONFIGURATION-AND-SECRETS.md)
- [Terraform procedure](procedures/TERRAFORM-PROVISIONING-PROCEDURE.md)

## Topology

```text
k8s-worker-01  192.168.0.50  pve1
k8s-worker-02  192.168.0.51  pve2
k8s-master-01  192.168.0.52  pve3
```

## Prepare Variables

```bash
cp -n terraform.tfvars.example terraform.tfvars
chmod 600 terraform.tfvars
git check-ignore -v terraform.tfvars
```

Do not overwrite a populated local variable file.

## HCP Terraform

Configure the organization and workspace in the Terraform `cloud` block, then:

```bash
terraform login
terraform init
```

The cloud block is backend configuration and cannot use normal Terraform input variables.

## Standard Workflow

```bash
terraform fmt -recursive
terraform validate
terraform plan
terraform apply
```

Review every plan before applying it.

## Destruction

```bash
terraform plan -destroy
terraform destroy
```

Destruction removes the Kubernetes VMs. Until backup restoration is implemented, cluster-local persistent application data is not recoverable from Git alone.

## State

HCP Terraform stores the current remote state for the configured workspace.

Useful commands:

```bash
terraform state list
terraform show
terraform output
```

Do not manually edit state.

## Boundaries

Terraform does not:

- Configure Fedora after cloud-init.
- Install Kubernetes or containerd.
- Run kubeadm.
- Install Cilium.
- Bootstrap Flux.
- Create the Flux SOPS Secret.
- Deploy Kubernetes applications.
- Restore persistent application data.

## Pre-Commit Validation

```bash
terraform fmt -recursive
terraform validate
git diff --check
git status --short
```
