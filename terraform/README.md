# Homelab Terraform

This directory provisions three Fedora Cloud virtual machines across an existing Proxmox VE cluster.

Terraform owns VM infrastructure only. Ansible owns the operating-system and Kubernetes lifecycle, while Flux owns Kubernetes platform and application resources.

## Requirements

- Healthy Proxmox VE cluster
- Existing storage IDs and network bridges
- Dedicated Proxmox API identity and token
- Controller access to the Proxmox API
- HCP Terraform organization/workspace or an adapted backend
- Local `terraform.tfvars`
- SSH public key matching the Ansible controller's private key

See:

- [Environment setup](../docs/ENVIRONMENT-SETUP.md)
- [Terraform procedure](procedures/TERRAFORM-PROVISIONING-PROCEDURE.md)
- [Configuration and secrets](../docs/CONFIGURATION-AND-SECRETS.md)

## Topology

```text
k8s-worker-01  192.168.0.50
k8s-worker-02  192.168.0.51
k8s-master-01  192.168.0.52
```

## Files

```text
terraform/
├── .terraform.lock.hcl
├── README.md
├── main.tf
├── output.tf
├── providers.tf
├── variables.tf
├── terraform.tfvars.example
├── terraform.tfvars
└── procedures/
    └── TERRAFORM-PROVISIONING-PROCEDURE.md
```

## Prepare Variables

```bash
cp terraform.tfvars.example terraform.tfvars
chmod 600 terraform.tfvars
git check-ignore -v terraform.tfvars
```

## HCP Terraform

Replace the organization and workspace in the `cloud` block, then:

```bash
terraform login
terraform init
```

The cloud block uses static configuration and cannot reference input variables.

## Standard Workflow

```bash
terraform fmt -recursive
terraform validate
terraform plan
terraform apply
```

## Destruction

```bash
terraform plan -destroy
terraform destroy
```

Until backup restoration exists, cluster-local application data is lost.

## Boundaries

Terraform does not configure Fedora, install Kubernetes, run kubeadm, install Cilium, bootstrap Flux, deploy applications, or restore backups.

## State

HCP Terraform stores remote state for the configured workspace. Do not commit or manually edit local state.

```bash
terraform state list
terraform show
terraform output
```

## Pre-Commit Validation

```bash
terraform fmt -recursive
terraform validate
git diff --check
git status --short
```
