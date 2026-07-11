# Flux Platform Bootstrap Procedure

## Purpose

Install Flux, connect Kubernetes to GitHub, and validate the complete GitOps hierarchy.

## Preconditions

- `cluster-bootstrap.yml` completed.
- Kubernetes API is Ready.
- Flux repository owner, repository, branch, and path are correct.
- The GitOps skeleton is pushed.
- The operator can create a repository deploy key.

## Validate

```bash
cd /home/stoof/GitHub/homelab/ansible
ansible-playbook playbooks/platform-bootstrap.yml --syntax-check
ansible-lint playbooks/platform-bootstrap.yml
```

## First Run: GitHub PAT

Create a fine-grained PAT restricted to this repository with Contents read/write, Metadata read, and enough Administration access to create the deploy key.

```bash
read -rsp "GitHub token: " GITHUB_TOKEN
echo
export GITHUB_TOKEN
```

Verify:

```bash
curl -fsS   -H "Authorization: Bearer $GITHUB_TOKEN"   https://api.github.com/user
```

## Execute

```bash
ansible-playbook playbooks/platform-bootstrap.yml
```

The first run installs and checksum-verifies Flux, bootstraps GitHub, creates an SSH deploy key, pushes `clusters/homelab/flux-system`, installs controllers, validates authentication, checks the branch, and waits for all Kustomizations.

## Remove PAT

```bash
unset GITHUB_TOKEN
test -z "${GITHUB_TOKEN:-}" && echo "GitHub token removed"
```

## Pull Flux Commit

```bash
cd /home/stoof/GitHub/homelab
git pull --rebase origin main
```

## Validate

```bash
ssh stoof@192.168.0.52   'sudo flux get all --all-namespaces --kubeconfig=/etc/kubernetes/admin.conf'
```

Expected Kustomizations:

```text
flux-system                 Ready=True
infrastructure-controllers  Ready=True
infrastructure-configs      Ready=True
applications                Ready=True
```

## Idempotency

Without the PAT:

```bash
cd ansible
ansible-playbook playbooks/platform-bootstrap.yml
```

Expected:

```text
changed=0
failed=0
```
