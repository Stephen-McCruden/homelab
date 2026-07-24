# Homelab Ansible

This directory contains the three deployment stages used after Terraform provisions the Fedora virtual machines.

```bash
ansible-playbook playbooks/system-init.yml
ansible-playbook playbooks/cluster-bootstrap.yml
ansible-playbook playbooks/platform-bootstrap.yml
```

Run Ansible as the normal controller user. The playbooks handle remote privilege escalation.

## YubiKey and Standard SSH

### YubiKey-backed SSH

From `ansible/`:

```bash
../scripts/ansible-yubikey playbooks/system-init.yml
../scripts/ansible-yubikey playbooks/cluster-bootstrap.yml
../scripts/ansible-yubikey playbooks/platform-bootstrap.yml
```

The wrapper defaults to:

```text
~/.ssh/id_ed25519_sk
```

Override it with:

```bash
export ANSIBLE_YUBIKEY_PATH="$HOME/.ssh/another-key"
```

### Standard file-based SSH key

Reference the private key in inventory or group variables, then run normal `ansible-playbook` commands.

See [Controller authentication](../docs/CONTROLLER-AUTHENTICATION.md).

## Stage Responsibilities

### `system-init.yml`

- Reconcile replaced VM SSH host keys.
- Validate inventory, Fedora, and sudo.
- Control DNF5 transaction races.
- Install prerequisites, containerd, and Kubernetes packages.
- Configure kernel modules, sysctls, swap, zram, firewall, SSH hardening, and SELinux compatibility mode.
- Verify the resulting node state.

### `cluster-bootstrap.yml`

- Render kubeadm configuration.
- Initialize the control plane only when required.
- Join only missing workers.
- Generate temporary join credentials only when needed.
- Install Cilium only when absent.
- Validate the API, nodes, CoreDNS, Cilium, and system Pods.

### `platform-bootstrap.yml`

- Validate the Kubernetes API and administrative kubeconfig.
- Install and checksum-verify the pinned Flux CLI.
- Verify the controller-side SOPS age private key.
- Create the `flux-system` namespace if required.
- Create or update `flux-system/sops-age` before encrypted reconciliation.
- Bootstrap Flux against GitHub only when Flux is absent.
- Validate the generated SSH deploy-key Secret.
- Wait for Flux controllers, Git source, and every managed Kustomization.

## First Platform Bootstrap Environment

The GitHub token is required only for a new Flux bootstrap.

```bash
read -rsp "GitHub fine-grained token: " GITHUB_TOKEN
printf '\n'
export GITHUB_TOKEN
```

Optional SOPS key override:

```bash
export SOPS_AGE_KEY_FILE="/secure/path/keys.txt"
```

After the bootstrap:

```bash
unset GITHUB_TOKEN
unset SOPS_AGE_KEY_FILE
```

Do not save a real GitHub token in the tracked `platform-bootstrap.env.example` file.

## Procedures

- [System initialization](procedures/SYSTEM-INIT-PROCEDURE.md)
- [Cluster bootstrap](procedures/CLUSTER-BOOTSTRAP-PROCEDURE.md)
- [Platform bootstrap](procedures/PLATFORM-BOOTSTRAP-PROCEDURE.md)
- [Full rebuild](procedures/FULL-REBUILD-PROCEDURE.md)

## Validation

```bash
cd ansible
ansible-inventory --graph

ansible-playbook playbooks/system-init.yml --syntax-check
ansible-playbook playbooks/cluster-bootstrap.yml --syntax-check
ansible-playbook playbooks/platform-bootstrap.yml --syntax-check

ansible-lint playbooks/system-init.yml
ansible-lint playbooks/cluster-bootstrap.yml
ansible-lint playbooks/platform-bootstrap.yml

yamllint .
```

## Runtime Idempotency

Run each playbook a second time after a successful deployment.

A healthy run should report:

```text
failed=0
unreachable=0
```

Most state-enforcement tasks should report `ok`. Review any unexpected changes rather than treating every nonzero changed count as acceptable.

## Kubeconfig

Local administrative kubeconfig:

```text
~/.kube/homelab-admin.conf
```

```bash
export KUBECONFIG="$HOME/.kube/homelab-admin.conf"
```

Protect it with mode `0600` and do not commit it.

## Security Decisions

- Package GPG verification remains enabled.
- SSH password authentication is disabled only after key verification.
- Firewall access is source restricted.
- kubeadm join credentials are temporary.
- The GitHub PAT is used only for initial Flux bootstrap.
- Flux uses a generated read-only SSH deploy key after bootstrap.
- The SOPS age private key remains outside Git and is copied to the control-plane node only temporarily.
- SELinux permissive mode is a documented Fedora compatibility workaround.
