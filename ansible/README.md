# Homelab Ansible

This directory contains the configuration-management and Kubernetes-bootstrap automation for Fedora Cloud virtual machines provisioned by Terraform.

The normal workflow requires only two playbook commands:

```bash
ansible-playbook playbooks/system-init.yml
ansible-playbook playbooks/cluster-bootstrap.yml
```

Run Ansible as the normal controller user. Do not run `ansible-playbook` through local `sudo`; privilege escalation is applied only to tasks running on managed nodes.

---

## Current Capabilities

### `playbooks/system-init.yml`

Builds and validates the Kubernetes node baseline:

- Reconciles stale controller `known_hosts` entries after Terraform rebuilds
- Validates the controller, operating system, inventory, variables, and passwordless sudo
- Controls DNF5 metadata jobs and package transactions
- Recovers from corrupted cached RPM payloads without disabling GPG verification
- Installs Kubernetes prerequisites, `runc`, and `crictl`
- Loads and persists required kernel modules
- Applies Kubernetes sysctl settings
- Disables swap and zram
- Installs and configures containerd 2.x
- Verifies the effective systemd cgroup configuration
- Installs `kubelet`, `kubeadm`, and `kubectl`
- Configures a source-restricted firewalld zone
- Configures SELinux permissive mode for the current platform compatibility requirement
- Applies SSH key-only hardening
- Verifies services, swap, sysctls, SELinux, SSH, Kubernetes tools, and containerd

A successful second run should report `changed=0` for the managed nodes.

### `playbooks/cluster-bootstrap.yml`

Initializes and verifies the Kubernetes control plane:

- Detects the installed kubeadm version
- Renders a kubeadm `v1beta4` configuration
- Validates the rendered configuration
- Detects existing or inconsistent control-plane state
- Pre-pulls control-plane images
- Runs `kubeadm init` only when the node is uninitialized
- Waits for the Kubernetes API server
- Verifies API readiness and node registration
- Installs the administrative kubeconfig for the remote administrator
- Fetches the administrative kubeconfig to the controller

The playbook must not rerun `kubeadm init` after the control plane has been initialized.

---

## Directory Layout

```text
ansible/
├── ansible.cfg
├── README.md
├── inventory/
│   ├── hosts.yml
│   └── group_vars/
├── playbooks/
│   ├── system-init.yml
│   └── cluster-bootstrap.yml
├── roles/
│   ├── package_manager/
│   ├── prereqs/
│   ├── container_runtime/
│   ├── kubernetes_node/
│   ├── firewall/
│   ├── hardening/
│   ├── verification/
│   ├── kubeadm_config/
│   ├── control_plane/
│   └── kubeconfig/
├── scripts/
├── procedures/
└── docs/
```

Each role follows the standard Ansible layout where applicable:

```text
roles/<role_name>/
├── defaults/main.yml
├── tasks/main.yml
├── handlers/main.yml
└── templates/
```

---

## Prerequisites

The controller requires:

- Python
- Ansible Core
- `ansible-lint`
- `yamllint`
- OpenSSH client tools
- Network access to the provisioned nodes
- The private key matching the public key injected by Terraform

The current workstation environment uses a Python virtual environment for Ansible.

Activate it manually when required:

```bash
source ~/.venvs/ansible/bin/activate
```

The controller must be able to reach:

```text
192.168.0.50
192.168.0.51
192.168.0.52
```

This may be through the local network or a Tailscale subnet route.

---

## Inventory

The inventory defines one control plane and two workers:

```text
kubernetes_cluster
├── control_plane
│   └── k8s-master-01
└── workers
    ├── k8s-worker-01
    └── k8s-worker-02
```

Inspect the effective inventory with:

```bash
ansible-inventory --graph
```

Inventory and group variables must remain consistent with the addresses and usernames configured by Terraform.

---

## Normal Operation

From the `ansible/` directory:

```bash
ansible-playbook playbooks/system-init.yml
ansible-playbook playbooks/cluster-bootstrap.yml
```

Tags may be used during development or troubleshooting, but they are not part of the normal deployment procedure.

Do not manually run:

```text
kubeadm init
kubeadm join
```

Those actions belong in Ansible automation.

---

## Validation

Before committing changes:

```bash
ansible-playbook playbooks/system-init.yml --syntax-check
ansible-playbook playbooks/cluster-bootstrap.yml --syntax-check
ansible-lint playbooks/system-init.yml
ansible-lint playbooks/cluster-bootstrap.yml
yamllint .
```

Runtime validation requires more than syntax checks. Test both first-run convergence and second-run idempotency against fresh Terraform-provisioned VMs.

A full current test sequence is:

```bash
ansible-playbook playbooks/system-init.yml
ansible-playbook playbooks/system-init.yml

ansible-playbook playbooks/cluster-bootstrap.yml
ansible-playbook playbooks/cluster-bootstrap.yml
```

Expected properties:

- The second `system-init.yml` run reports no changes.
- The second `cluster-bootstrap.yml` run does not rerun `kubeadm init`.
- All assertions pass.
- No hosts are failed or unreachable.

---

## Design Guarantees

- No unconditional `dnf5 makecache --refresh` on every run
- GPG package verification remains enabled
- Package-cache recovery occurs only after a failed transaction
- Automatic DNF metadata jobs are prevented from colliding with Ansible
- Controller SSH host-key reconciliation supports Terraform rebuilds
- Local controller tasks do not inherit remote privilege escalation
- SSH password authentication is disabled only after an authorized key is verified
- containerd uses systemd cgroups
- Swap and zram remain disabled
- kubeadm initialization is guarded by persistent state checks
- A partial control-plane state causes a controlled failure rather than a destructive retry
- Administrative kubeconfig files are not committed to Git
- Second-run idempotency is a release requirement

---

## SELinux Compatibility Decision

SELinux remains installed and enabled but is configured in permissive mode on Kubernetes nodes.

During control-plane bootstrap on the current Fedora 44 and containerd stack, SELinux enforcement blocked kubeadm static Pods from accessing required paths, including `/var/lib/etcd` and Kubernetes certificate and kubeconfig files. Permissive mode allows the cluster to operate while retaining AVC audit records for future policy analysis.

This is a documented compatibility workaround, not a claim that permissive mode provides the same protection as enforcing mode. Returning to enforcing mode remains a future hardening task after a tested policy solution is available.

---

## Kubeconfig

The control-plane bootstrap playbook installs the administrative kubeconfig on the control-plane node and retrieves a copy to the controller.

Current controller path:

```text
/home/stoof/.kube/homelab-admin.conf
```

Use it explicitly when required:

```bash
export KUBECONFIG=/home/stoof/.kube/homelab-admin.conf
kubectl get nodes -o wide
```

The file grants administrative cluster access and must not be committed to Git.

---

## Next Implementation Phase

The next roles will add:

- Cilium installation
- Worker join-token creation
- Worker `JoinConfiguration`
- Worker-node joining
- CoreDNS readiness checks
- Cross-node networking tests
- Complete cluster-health verification
- Flux bootstrap
