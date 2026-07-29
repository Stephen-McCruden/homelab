# Kubernetes Cluster Bootstrap Procedure

## Purpose

Initialize the single control-plane node, join workers, reconcile secure
kubelet serving certificates, install Cilium, and validate cluster health.

## Preconditions

- `system-init.yml` completed on every node.
- containerd, kubelet, firewalld, and time synchronization are healthy.
- swap and zram are disabled.
- kubeadm endpoint, Pod CIDR, Service CIDR, and inventory are correct.
- node firewalls allow required Kubernetes and Cilium traffic.

## Preflight

```bash
cd /path/to/homelab/ansible

ansible-playbook playbooks/cluster-bootstrap.yml --syntax-check
ansible-lint --profile min playbooks/cluster-bootstrap.yml
```

Confirm the endpoint is unused on a fresh build and reachable after init:

```text
<CONTROL_PLANE_IP>:6443
```

## Execute

YubiKey:

```bash
../scripts/ansible-yubikey playbooks/cluster-bootstrap.yml
```

File-backed key:

```bash
ansible-playbook playbooks/cluster-bootstrap.yml
```

## Expected Sequence

```text
render kubeadm configuration
  -> initialize or verify control plane
  -> retrieve administrative kubeconfig
  -> prepare all nodes for Cilium
  -> detect unjoined workers
  -> generate temporary join credentials only when needed
  -> join missing workers one at a time
  -> reconcile serverTLSBootstrap on every kubelet
  -> verify workers exist in the API
  -> install or verify Cilium
  -> validate API, nodes, Cilium, CoreDNS, and system Pods
```

## Acceptance

```bash
export KUBECONFIG="$HOME/.kube/homelab-admin.conf"
chmod 600 "$KUBECONFIG"

kubectl get --raw=/readyz
kubectl get nodes -o wide
kubectl get pods --namespace kube-system -o wide
kubectl get ciliumnodes
```

Expected nodes:

```text
k8s-master-01  Ready
k8s-worker-01  Ready
k8s-worker-02  Ready
```

CoreDNS and Cilium must be healthy. Kubelet serving CSRs may remain pending
until the Flux-managed approver is installed in the next stage.

## Secure Kubelet Serving Certificates

The intended design uses:

```yaml
serverTLSBootstrap: true
```

Ansible writes it to kubeadm's cluster configuration and each node's active
kubelet configuration, restarting kubelet only when required. Later, Flux
installs an approver restricted by expected node names and addresses.

Inspect:

```bash
kubectl get certificatesigningrequests \
  --output custom-columns='NAME:.metadata.name,SIGNER:.spec.signerName,REQUESTOR:.spec.username,CONDITIONS:.status.conditions[*].type'
```

Do not manually approve an unverified request.

## Idempotency

Run the same playbook again. Expected:

- no second `kubeadm init`
- no rejoin of existing workers
- no unused token generation
- no unnecessary Cilium reinstall
- no repeated kubelet restart when configuration is already correct
- health checks execute again
- `failed=0` and `unreachable=0`

## Partial State

The playbook deliberately fails when only part of a kubeadm state exists. For a
disposable VM, reset or replace the affected node deliberately rather than
joining over unknown state.

Before destructive recovery, inspect:

```bash
sudo ls -l /etc/kubernetes /var/lib/kubelet
sudo systemctl status kubelet containerd
```

## Failure Isolation

### API not Ready

Inspect kubelet, containerd, static Pods, kubeadm config, certificates,
firewalld, and time.

### Worker join

Inspect endpoint reachability, token TTL, CA hash, CRI socket, kubelet logs,
firewall, and partial state.

### Cilium

Inspect required modules/sysctls, UDP `8472`, TCP `4240`, image pulls, Pod logs,
and node routes.

### CoreDNS

Confirm Cilium health and Pod-to-API TCP `6443`. Rerun `system-init.yml` if the
firewall role has not applied the required Pod CIDR rule.

### Local kubeconfig

Confirm the kubeconfig role completed and
`~/.kube/homelab-admin.conf` exists with mode `0600`.

Continue with [Platform bootstrap](PLATFORM-BOOTSTRAP-PROCEDURE.md).
