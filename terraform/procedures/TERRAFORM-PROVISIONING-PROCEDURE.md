# Terraform Provisioning Procedure

## Purpose

Create, update, replace, or deliberately destroy the Fedora Kubernetes virtual
machines managed by the selected HCP Terraform workspace.

## Preconditions

- [Environment setup](../../docs/ENVIRONMENT-SETUP.md) is complete.
- Proxmox has quorum and target nodes are online.
- Target storage IDs and bridge exist.
- API and provider SSH credentials work.
- HCP organization and workspace are correct.
- `terraform.tfvars` exists, is mode `0600`, and is ignored.
- the injected public SSH key matches the operator's private identity.
- any required persistent data has an external, tested backup.

## Enter the Repository

```bash
cd /path/to/homelab
REPO_ROOT="$(pwd)"
cd terraform
```

## Prepare and Validate

```bash
test -f terraform.tfvars
git check-ignore -v terraform.tfvars
terraform login
terraform init
terraform fmt -check -recursive
terraform validate
```

Confirm state belongs to the intended environment:

```bash
terraform state list
terraform show
```

## Plan

```bash
terraform plan -out=tfplan
```

Review:

- VM names and IDs
- Proxmox node placement
- CPU and memory
- datastore IDs
- root-disk size
- Fedora image URL and filename
- static addresses, gateway, and DNS
- injected public SSH keys
- all replacements and deletions

Stop if an existing VM or disk will be replaced unexpectedly.

## Apply

```bash
terraform apply tfplan
```

Remove the local saved plan after use:

```bash
rm -f ./tfplan
```

This removes only the explicitly named local plan file.

## Verify VM Readiness

```bash
for address in 192.168.0.50 192.168.0.51 192.168.0.52; do
  ping -c 2 "$address"
done
```

YubiKey-backed SSH:

```bash
for address in 192.168.0.50 192.168.0.51 192.168.0.52; do
  ssh -o IdentitiesOnly=yes \
    -i "$HOME/.ssh/id_ed25519_sk" \
    "stoof@${address}" true
done
```

File-backed SSH:

```bash
for address in 192.168.0.50 192.168.0.51 192.168.0.52; do
  ssh -o BatchMode=yes \
    -o IdentitiesOnly=yes \
    -i "$HOME/.ssh/id_ed25519" \
    "stoof@${address}" true
done
```

On at least one node:

```bash
ip route
resolvectl status
getent hosts dl.fedoraproject.org
```

## Continue

```bash
cd "$REPO_ROOT/ansible"
../scripts/ansible-yubikey playbooks/system-init.yml
```

Or use `ansible-playbook` with a file-backed key.

## Planned Destruction

Use the full rebuild runbook. Immediately before destruction:

```bash
git status --short
git rev-parse HEAD
terraform state list
terraform plan -destroy
```

Confirm the workspace, Git state, SOPS recovery identity, Azure secrets,
Terraform variables, SSH keys, and external application backups.

Then:

```bash
terraform destroy
```

## Failure Isolation

### Authentication

Check API URL, token ID and secret, ACLs, privilege separation, TLS mode, SSH
access to Proxmox hosts, and clock synchronization.

### Storage or bridge

The exact storage ID and bridge must exist on every Proxmox node referenced by
`k8s_nodes`.

### Image download

Verify the URL, Proxmox outbound DNS/HTTPS, import datastore, free space, and
content type.

### SSH

Verify cloud-init completion, username, injected public key, route, TCP `22`,
and stale host keys. `system-init.yml` owns normal host-key reconciliation after
replacement.

Do not hand-configure a Terraform-created VM as the permanent fix. Correct
Terraform or the documented prerequisite and recreate it.
