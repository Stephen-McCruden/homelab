# Swap Instructions

This package contains replacement documentation and example files. It does not contain Terraform code, Ansible roles, Kubernetes manifests, inventory files, or real secrets.

## Included Paths

```text
README.md
docs/
terraform/README.md
terraform/terraform.tfvars.example
terraform/procedures/TERRAFORM-PROVISIONING-PROCEDURE.md
ansible/README.md
ansible/FILE-MAP.md
ansible/platform-bootstrap.env.example
ansible/procedures/
```

## Back Up the Current Documentation

From the repository root:

```bash
backup_file="$HOME/homelab-docs-backup-$(date +%Y%m%d-%H%M%S).tar.gz"

tar -czf "$backup_file" \
  README.md \
  docs \
  terraform/README.md \
  terraform/terraform.tfvars.example \
  terraform/procedures \
  ansible/README.md \
  ansible/FILE-MAP.md \
  ansible/platform-bootstrap.env.example \
  ansible/procedures

printf 'Backup written to %s\n' "$backup_file"
```

This command copies documentation and examples only. It does not back up real local configuration such as `terraform.tfvars` or Ansible inventory.

## Copy the Replacement Files

Extract this package outside the repository, then copy its contents into the repository root:

```bash
cp -a homelab-documentation-suite/. /home/stoof/GitHub/homelab/
```

Review changes:

```bash
cd /home/stoof/GitHub/homelab
git status --short
git diff --stat
git diff
```

## Important Local Files

The replacement package does not include or overwrite:

```text
terraform/terraform.tfvars
ansible/inventory/hosts.yml
ansible/inventory/group_vars/all.yml
~/.config/sops/age/keys.txt
~/.kube/homelab-admin.conf
```

## Commit

After review:

```bash
git add README.md docs terraform/README.md \
  terraform/terraform.tfvars.example terraform/procedures \
  ansible/README.md ansible/FILE-MAP.md \
  ansible/platform-bootstrap.env.example ansible/procedures

git commit -m "Update deployment and recovery documentation"
git push
```
