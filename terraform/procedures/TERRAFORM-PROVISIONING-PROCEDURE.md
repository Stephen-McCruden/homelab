# Terraform Provisioning Procedure

## Purpose

Provision, update, destroy, or recreate the Fedora Kubernetes virtual machines on Proxmox VE.

## Preconditions

- `docs/ENVIRONMENT-SETUP.md` is satisfied.
- Proxmox quorum is healthy.
- Required storage and network bridges exist.
- The Proxmox API identity and token are valid.
- `terraform.tfvars` exists and is ignored.
- HCP Terraform organization and workspace values are correct.
- The controller has authenticated with HCP Terraform.
- The configured public SSH key matches the controller's private key.

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

Review:

- VM names and IDs.
- Proxmox node placement.
- CPU and memory.
- VM disk storage and size.
- Import storage.
- Network bridge.
- Static addresses and gateway.
- Injected SSH public keys.
- Any replacement or destroy action.

## Apply

```bash
terraform apply
```

Wait for cloud-init to finish, then test network reachability:

```bash
ping -c 2 192.168.0.50
ping -c 2 192.168.0.51
ping -c 2 192.168.0.52
```

SSH is the required validation.

### Normal file-based SSH key

```bash
ssh -o BatchMode=yes \
  -o IdentitiesOnly=yes \
  -i "$HOME/.ssh/id_ed25519" \
  YOUR_ADMIN_USERNAME@192.168.0.52 true
```

### YubiKey-backed SSH key

Do not use `BatchMode=yes` when the key requires a PIN prompt.

```bash
ssh -o IdentitiesOnly=yes \
  -i "$HOME/.ssh/id_ed25519_sk" \
  YOUR_ADMIN_USERNAME@192.168.0.52 true
```

Repeat the SSH test for both worker addresses.

## Continue to Ansible

```bash
cd ../ansible
```

Without a YubiKey:

```bash
ansible-playbook playbooks/system-init.yml
```

With YubiKey-backed SSH:

```bash
../scripts/ansible-yubikey playbooks/system-init.yml
```

## Destroy

Before destroying, confirm:

- The correct HCP workspace is active.
- Git contains the desired declarative state.
- Local inventory and secret files are available.
- The SOPS age private key is backed up.
- Important application data is backed up outside the cluster.

Then:

```bash
terraform plan -destroy
terraform destroy
```

## Troubleshooting

### Proxmox authentication

Check:

- API URL.
- Token ID.
- Token secret.
- User and token ACLs.
- Privilege separation.
- Controller and Proxmox clocks.

### Storage or bridge errors

The selected storage and bridge must exist on every Proxmox node referenced by `k8s_nodes`.

### Fedora image download

Verify:

- The current Fedora Cloud image URL.
- Outbound HTTPS from each required Proxmox node.
- Free space on the import datastore.
- Correct image filename and content type.

### SSH failure

Verify:

- cloud-init completed.
- The username is correct.
- The injected public key matches the controller key.
- Routing and TCP 22 work.
- The old host key is reconciled after VM replacement.
