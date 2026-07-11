# Deployment Workflow

## First-Time Deployment

### 1. Prepare local configuration

```bash
cp terraform/terraform.tfvars.example terraform/terraform.tfvars
```

Review and adapt Ansible inventory and group variables.

### 2. Provision VMs

```bash
cd terraform
terraform init
terraform fmt -recursive
terraform validate
terraform plan
terraform apply
```

### 3. Prepare nodes

```bash
cd ../ansible
ansible-playbook playbooks/system-init.yml
```

### 4. Build the cluster

```bash
ansible-playbook playbooks/cluster-bootstrap.yml
```

### 5. Bootstrap Flux

First run only:

```bash
read -rsp "GitHub token: " GITHUB_TOKEN
echo
export GITHUB_TOKEN
ansible-playbook playbooks/platform-bootstrap.yml
unset GITHUB_TOKEN
```

Pull Flux's generated commit:

```bash
cd ..
git pull --rebase origin main
```

### 6. Verify idempotency

```bash
cd ansible
ansible-playbook playbooks/system-init.yml
ansible-playbook playbooks/cluster-bootstrap.yml
ansible-playbook playbooks/platform-bootstrap.yml
```

Expected:

```text
changed=0
failed=0
```

## Normal Changes

Infrastructure changes go through Terraform plan/apply. Node or cluster automation changes go through the affected Ansible playbook and a second idempotency run. Kubernetes platform and application changes go under `kubernetes/` and are reconciled by Flux after commit and push.

## Current Full Rebuild

```bash
cd terraform
terraform destroy
terraform apply

cd ../ansible
ansible-playbook playbooks/system-init.yml
ansible-playbook playbooks/cluster-bootstrap.yml
ansible-playbook playbooks/platform-bootstrap.yml
```

Flux restores declarative state from Git. Persistent application data requires the future backup stage.
