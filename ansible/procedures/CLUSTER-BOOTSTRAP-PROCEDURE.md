# Kubernetes Cluster Bootstrap Procedure

## Purpose

Initialize the control plane, join required workers, install Cilium, and validate the cluster.

## Preconditions

- `system-init.yml` completed successfully.
- containerd and kubelet are installed.
- Swap is disabled.
- The endpoint and inventory are correct.
- The nodes can reach package and image registries.

## Preflight

```bash
cd /home/stoof/GitHub/homelab/ansible
ansible-playbook playbooks/cluster-bootstrap.yml --syntax-check
ansible-lint playbooks/cluster-bootstrap.yml
```

## Execute

```bash
ansible-playbook playbooks/cluster-bootstrap.yml
```

## Expected First Run

- Render and validate kubeadm configuration
- Initialize the control plane
- Wait for API readiness
- Fetch the admin kubeconfig
- Configure Cilium ports
- Detect workers requiring join
- Generate a token only when needed
- Join uninitialized workers
- Install and validate Cilium
- Validate all nodes, CoreDNS, API, and system Pods

## Validate

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

```bash
ansible-playbook playbooks/cluster-bootstrap.yml
```

Expected:

- `kubeadm init` skipped
- Workers not rejoined
- No unused token
- Cilium install skipped
- Health checks rerun
- `changed=0`

## Partial State

The playbook fails on inconsistent kubeadm state. Deliberately reset or rebuild the affected node rather than forcing a join over partial state.

## Kubelet Serving CSRs

Pending serving CSRs may affect `exec`, logs, port-forwarding, or kubelet streaming. Do not automatically approve arbitrary CSRs without validating requestor and node identity.
