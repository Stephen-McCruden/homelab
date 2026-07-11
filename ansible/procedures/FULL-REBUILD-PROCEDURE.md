# Full Rebuild Procedure

## Purpose

Recreate cluster infrastructure and declarative platform state after deliberate destroy or VM loss.

## Current Limitation

This restores VMs, Fedora configuration, Kubernetes, Cilium, Flux, and Git-managed resources. It does not yet restore databases, uploads, PVC data, or recovery secrets.

## Before Destroy

```bash
cd /home/stoof/GitHub/homelab
git status
git pull --rebase origin main
```

Confirm a clean tree, pushed desired state, accessible Terraform state, local configuration files, and external backups for anything important.

## Destroy and Recreate

```bash
cd terraform
terraform plan -destroy
terraform destroy
terraform apply
```

## Rebuild Stages

```bash
cd ../ansible
ansible-playbook playbooks/system-init.yml
ansible-playbook playbooks/cluster-bootstrap.yml
ansible-playbook playbooks/platform-bootstrap.yml
```

A replacement cluster does not retain the destroyed cluster's Flux Secret. A fresh PAT may be required to bootstrap a new deploy key.

## Verify

```bash
export KUBECONFIG="$HOME/.kube/homelab-admin.conf"
kubectl get nodes -o wide
kubectl get pods -A

ssh stoof@192.168.0.52   'sudo flux get all --all-namespaces --kubeconfig=/etc/kubernetes/admin.conf'
```

## Idempotency

Run all stages again. A healthy deployment should show `changed=0` and `failed=0`.

## Future Complete Recovery

The final process will add:

```bash
ansible-playbook playbooks/backup-bootstrap.yml
```

That stage will reconnect external backup storage, restore encrypted secrets and data, verify applications, and measure RTO/RPO.
