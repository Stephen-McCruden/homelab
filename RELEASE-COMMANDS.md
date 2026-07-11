# Documentation Milestone Commit and Release

## Install the bundle

Copy the generated files into the repository root, preserving paths. Review `.gitignore.additions` and merge the appropriate lines into `.gitignore`; do not commit the helper file itself unless you want to retain it as documentation.

## Validate

```bash
cd /home/stoof/GitHub/homelab

terraform -chdir=terraform fmt -recursive
terraform -chdir=terraform validate

cd ansible
ansible-playbook playbooks/system-init.yml --syntax-check
ansible-playbook playbooks/cluster-bootstrap.yml --syntax-check
ansible-playbook playbooks/platform-bootstrap.yml --syntax-check
ansible-lint playbooks/system-init.yml
ansible-lint playbooks/cluster-bootstrap.yml
ansible-lint playbooks/platform-bootstrap.yml
yamllint .

cd ..
git diff --check
git status --short
git check-ignore -v terraform/terraform.tfvars
```

## Review

```bash
git diff -- README.md
git diff -- ansible/README.md
git diff -- terraform/README.md
git diff -- docs ansible/procedures terraform/procedures
git diff -- .gitignore
```

Confirm no real secret is present:

```bash
git diff | grep -Ei   'password|secret|token|private.?key|api.?key'
```

Review every match; placeholders and documentation references are expected.

## Stage

```bash
git add   README.md   docs   terraform/README.md   terraform/terraform.tfvars.example   terraform/procedures   ansible/README.md   ansible/inventory/hosts.yml.example   ansible/inventory/group_vars/all.yml.example   ansible/platform-bootstrap.env.example   ansible/procedures   .gitignore
```

Do not stage:

```text
terraform/terraform.tfvars
private SSH keys
administrative kubeconfig
real environment files
```

## Commit

```bash
git diff --cached --check
git diff --cached --stat
git diff --cached

git commit   -m "docs: publish reproducible deployment procedures"   -m "Document external prerequisites, Proxmox API integration, Terraform provisioning, all three idempotent Ansible stages, full rebuild boundaries, secret handling, and safe example configuration files."
```

## Push

```bash
git pull --rebase origin main
git push origin main
```

## Tag

Recommended tag:

```text
v0.4.0
```

This milestone is larger than a documentation-only patch because it establishes a reproducible operator and contributor interface around the now-working Terraform, Kubernetes, Cilium, and Flux pipeline.

```bash
git tag -a v0.4.0   -m "Reproducible deployment documentation"   -m "Adds environment prerequisites, Proxmox API setup guidance, Terraform and Ansible procedures, safe configuration templates, GitOps documentation, and the current full-rebuild runbook."

git show --stat v0.4.0
git push origin v0.4.0
```

## Suggested GitHub Release

Title:

```text
v0.4.0 — Reproducible Deployment Documentation
```

Summary:

```text
This release turns the working homelab automation into a documented, reproducible deployment workflow.

Included:
- External environment and Proxmox integration prerequisites
- Dedicated Proxmox API identity and token guidance
- HCP Terraform integration requirements
- Terraform provisioning and rebuild procedure
- Updated system-init procedure
- Cluster bootstrap procedure
- Flux platform bootstrap procedure
- Current full-rebuild procedure and recovery boundaries
- Public-safe Terraform and Ansible configuration examples
- Secret and kubeconfig handling guidance
- Updated root, Terraform, and Ansible READMEs

The current automated stages are Terraform provisioning, node initialization, Kubernetes/Cilium bootstrap, and Flux GitOps bootstrap. Backup and persistent-data restoration remain the next major platform milestone.
```
