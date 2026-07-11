# Terraform Provisioning Procedure

## Purpose

Provision, update, destroy, or rebuild the Fedora Kubernetes virtual machines on Proxmox VE.

## Preconditions

- `docs/ENVIRONMENT-SETUP.md` is satisfied.
- Proxmox cluster quorum is healthy.
- Storage and network bridges exist.
- The API token is valid.
- `terraform.tfvars` exists and is ignored.
- HCP Terraform organization/workspace values are correct.
- The controller has authenticated with HCP Terraform.

## Prepare

```bash
cd /home/stoof/GitHub/homelab/terraform
cp -n terraform.tfvars.example terraform.tfvars
chmod 600 terraform.tfvars
git check-ignore -v terraform.tfvars
terraform login
terraform init
```

Do not overwrite an existing populated `terraform.tfvars`.

## Validate

```bash
terraform fmt -recursive
terraform validate
```

## Plan

```bash
terraform plan
```

Review VM names, node placement, VM IDs, resources, storage, bridge, addresses, keys, and destructive actions.

## Apply

```bash
terraform apply
```

Confirm reachability:

```bash
ping -c 2 192.168.0.50
ping -c 2 192.168.0.51
ping -c 2 192.168.0.52
```

SSH is the authoritative requirement:

```bash
ssh -o BatchMode=yes YOUR_ADMIN_USERNAME@192.168.0.50 true
ssh -o BatchMode=yes YOUR_ADMIN_USERNAME@192.168.0.51 true
ssh -o BatchMode=yes YOUR_ADMIN_USERNAME@192.168.0.52 true
```

## Continue

```bash
cd ../ansible
ansible-playbook playbooks/system-init.yml
```

## Destroy

Confirm external backups, the active HCP workspace, and the destroy plan:

```bash
terraform plan -destroy
terraform destroy
```

Until backup restoration is complete, destruction removes cluster-local workload state.

## Rebuild

```bash
terraform apply

cd ../ansible
ansible-playbook playbooks/system-init.yml
ansible-playbook playbooks/cluster-bootstrap.yml
ansible-playbook playbooks/platform-bootstrap.yml
```

## Troubleshooting

### Authentication

Check API URL, token ID, token secret, ACLs, privilege separation, and clocks.

### Storage or bridge

The selected storage and bridge must exist on every target node referenced by `k8s_nodes`.

### Image download

Verify the Fedora URL, outbound HTTPS, and free import-datastore space.

### SSH

Verify the public key, matching private key, cloud-init completion, username, routing, and TCP 22.
