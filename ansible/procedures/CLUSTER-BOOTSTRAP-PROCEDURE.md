# Kubernetes Cluster Bootstrap Procedure

## Purpose

Initialize the control plane, join required workers, install Cilium, and validate the Kubernetes cluster.

## Preconditions

- `system-init.yml` completed successfully.
- containerd and kubelet are installed and running.
- Swap and zram are disabled.
- Inventory and kubeadm endpoint values are correct.
- Nodes can reach package and container registries.
- Node-to-node firewall rules allow required Kubernetes and Cilium traffic.

## Preflight

```bash
cd /home/stoof/GitHub/homelab/ansible
ansible-playbook playbooks/cluster-bootstrap.yml --syntax-check
ansible-lint playbooks/cluster-bootstrap.yml
```

## Execute

Without a YubiKey:

```bash
ansible-playbook playbooks/cluster-bootstrap.yml
```

With YubiKey-backed SSH:

```bash
../scripts/ansible-yubikey playbooks/cluster-bootstrap.yml
```

## Expected First Run

- Render and validate kubeadm configuration.
- Initialize the control plane.
- Wait for Kubernetes API readiness.
- Retrieve the administrative kubeconfig.
- Apply node-level Cilium prerequisites.
- Detect workers that require joining.
- Generate a join token only when required.
- Join uninitialized workers.
- Install and validate Cilium.
- Validate nodes, CoreDNS, API readiness, Cilium, and system Pods.

## Validate Locally

```bash
export KUBECONFIG="$HOME/.kube/homelab-admin.conf"

kubectl get nodes -o wide
kubectl get pods -A
kubectl get --raw=/readyz
```

Expected nodes:

```text
k8s-master-01  Ready
k8s-worker-01  Ready
k8s-worker-02  Ready
```

## Idempotency

Run the same playbook command again.

Expected behavior:

- `kubeadm init` is skipped.
- Existing workers are not rejoined.
- No unused join token is generated.
- Existing Cilium installation is not recreated unnecessarily.
- Health checks run again.
- No failures or unreachable hosts occur.

## Partial kubeadm State

The playbook should fail when a node is in inconsistent partial state. Deliberately reset or rebuild the affected node instead of forcing a new join over unknown kubeadm state.

## Kubelet Serving Certificates

The kubelet configuration must enable server TLS bootstrap so kubelet serving certificates can be issued with valid node address SANs.

The kubelet CSR approver is installed through Flux later, so initial serving CSR behavior must be understood during the bootstrap boundary.

After the platform is deployed, verify:

```bash
kubectl get certificatesigningrequests
```

Approve only CSRs whose signer, requestor, node identity, and requested addresses are expected. Do not enable blanket approval of arbitrary CSRs.

## Failure Handling

### API not Ready

Check static Pods, kubelet, containerd, host firewall, kubeadm configuration, and control-plane logs.

### Worker does not join

Check the join token, CA hash, API endpoint, time synchronization, firewall, containerd, kubelet, and partial kubeadm state.

### Cilium not Ready

Check node routes, Cilium-required ports, kernel modules, sysctls, image pulls, and Cilium Pod logs.

### Local kubeconfig missing

Verify the kubeconfig role completed and that `~/.kube/homelab-admin.conf` is mode `0600`.
