# Configuration and Secrets

This repository is public. Real credentials, private keys, recovery keys, kubeconfigs, and environment-specific secret values must never be committed.

## Tracked Examples vs Local Files

Tracked example files:

```text
terraform/terraform.tfvars.example
ansible/inventory/hosts.yml.example
ansible/inventory/group_vars/all.yml.example
ansible/platform-bootstrap.env.example
```

Local files containing real values:

```text
terraform/terraform.tfvars
ansible/inventory/hosts.yml
ansible/inventory/group_vars/all.yml
```

## Terraform Variables

```bash
cp terraform/terraform.tfvars.example terraform/terraform.tfvars
chmod 600 terraform/terraform.tfvars
git check-ignore -v terraform/terraform.tfvars
```

The file may contain Proxmox API values, storage IDs, public SSH keys, static addresses, and resource sizing. Never place a private SSH key in Terraform input.

## Ansible Inventory

```bash
cp ansible/inventory/hosts.yml.example ansible/inventory/hosts.yml
cp ansible/inventory/group_vars/all.yml.example   ansible/inventory/group_vars/all.yml
```

The private-key path references a local controller file. The key itself stays outside Git.

## Flux Bootstrap PAT

Load it interactively:

```bash
read -rsp "GitHub token: " GITHUB_TOKEN
echo
export GITHUB_TOKEN
```

Verify without printing it:

```bash
curl -fsS   -H "Authorization: Bearer $GITHUB_TOKEN"   https://api.github.com/user
```

After bootstrap:

```bash
unset GITHUB_TOKEN
test -z "${GITHUB_TOKEN:-}" && echo "GitHub token removed"
```

## Kubernetes Kubeconfig

The controller kubeconfig is:

```text
~/.kube/homelab-admin.conf
```

Protect it:

```bash
chmod 600 ~/.kube/homelab-admin.conf
```

Do not commit it.

## Future Secret Strategy

Before public-facing applications are deployed, use encrypted Git-managed secrets such as SOPS with age.

The age private key must be stored outside the cluster and Git, backed up independently, and available during disaster recovery.

Backup destination credentials and recovery material will be handled by the future `backup-bootstrap.yml`.

## Pre-Commit Review

```bash
git status --short
git diff --cached --check
git diff --cached
git check-ignore -v terraform/terraform.tfvars
```

Optional heuristic:

```bash
git diff --cached | grep -Ei   'password|secret|token|private.?key|api.?key'
```
