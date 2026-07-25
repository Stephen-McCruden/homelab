# Terraform: Proxmox Virtual Machines

This directory creates the Fedora Cloud virtual machines used by Kubernetes.
It assumes that Proxmox, its storage, network bridges, API identity, and HCP
Terraform workspace already exist.

## Ownership Boundary

Terraform owns:

- Fedora Cloud image downloads on target Proxmox nodes
- VM names, IDs, placement, CPU, memory, boot disk, and NIC
- cloud-init username, public SSH keys, static address, gateway, and DNS

Terraform does not own:

- Fedora configuration after cloud-init
- containerd or Kubernetes
- Cilium
- Flux
- Kubernetes controllers or applications
- router rules, public DNS, Azure Key Vault, or application-data restore

See [Architecture](../docs/ARCHITECTURE.md).

## Reference Topology

| VM | Proxmox | VM ID | Address | CPU | Memory |
|---|---|---:|---:|---:|---:|
| `k8s-worker-01` | `pve1` | 150 | `192.168.0.50/24` | 4 | 8192 MiB |
| `k8s-worker-02` | `pve2` | 151 | `192.168.0.51/24` | 4 | 8192 MiB |
| `k8s-master-01` | `pve3` | 152 | `192.168.0.52/24` | 4 | 8192 MiB |

## Requirements

- healthy Proxmox cluster with quorum
- target datastores and bridge on every selected node
- dedicated Proxmox API token
- provider SSH access to Proxmox hosts
- existing HCP Terraform organization and CLI-driven workspace
- local `terraform.tfvars`
- public SSH key matching the Ansible controller identity

See [Environment setup](../docs/ENVIRONMENT-SETUP.md).

## Local Variables

```bash
cp -n terraform.tfvars.example terraform.tfvars
chmod 600 terraform.tfvars
git check-ignore -v terraform.tfvars
```

Replace every placeholder. The example intentionally contains no real
credential.

The current `variables.tf` default and example disagree on root-disk size. Set
`vm_disk_size` explicitly in `terraform.tfvars` until that implementation
decision is corrected. Longhorn should later use a separate virtual disk rather
than consuming the root disk.

## Backend

The HCP configuration is in `main.tf`:

```text
Organization: stoof-homelab
Workspace:    stoof-lab
```

A reproducer must replace those values:

```bash
terraform login
terraform init
```

## Validate and Apply

```bash
terraform fmt -check -recursive
terraform validate
terraform plan -out=tfplan
terraform apply tfplan
```

Review every create, replacement, and delete action. A saved plan can contain
sensitive data and must not be committed.

## Acceptance

After cloud-init:

```bash
for address in 192.168.0.50 192.168.0.51 192.168.0.52; do
  ping -c 2 "$address"
done
```

Then test SSH. For YubiKey:

```bash
ssh -o IdentitiesOnly=yes \
  -i "$HOME/.ssh/id_ed25519_sk" \
  stoof@192.168.0.52 true
```

Also verify routing and DNS from a VM:

```bash
ip route
resolvectl status
getent hosts registry.k8s.io
```

Continue with [System initialization](../ansible/procedures/SYSTEM-INIT-PROCEDURE.md).

## State

```bash
terraform state list
terraform show
terraform output
```

Do not manually edit state. Treat state output as sensitive because provider
state may contain input values.

## Destruction

Use the
[full rebuild procedure](../ansible/procedures/FULL-REBUILD-PROCEDURE.md),
not a remembered `terraform destroy` command.

At minimum:

```bash
terraform plan -destroy
terraform destroy
```

Destruction removes the Kubernetes VMs. Git restores desired configuration, but
it does not restore etcd or application data. Require external backup and
restore evidence before destroying stateful workloads.

## Validation Before Commit

```bash
terraform fmt -check -recursive
terraform validate
git diff --check
git status --short
```

The provider constraint should eventually be pinned to the release proven by a
full rebuild rather than allowing every version newer than `0.65.0`.

See the
[Terraform provisioning procedure](procedures/TERRAFORM-PROVISIONING-PROCEDURE.md)
for the complete operator sequence.
