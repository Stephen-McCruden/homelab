# Troubleshooting

Start at the lowest incomplete layer and stop at the first real failure.

```text
Proxmox
  -> VM network and DNS
  -> SSH and sudo
  -> Fedora baseline
  -> containerd and kubelet
  -> Kubernetes API
  -> Cilium and CoreDNS
  -> Flux source
  -> Flux dependency
  -> HelmRelease
  -> configuration and Secrets
  -> Longhorn and PVC attachment
  -> application
  -> public or Tailscale ingress, DNS, and TLS
```

Do not change a later layer to hide an earlier failure.

## Collect a Baseline

```bash
git rev-parse HEAD
terraform version
ansible --version
kubectl version

kubectl get nodes -o wide
kubectl get pods --all-namespaces -o wide
kubectl get kustomizations --namespace flux-system
kubectl get helmreleases --all-namespaces
kubectl get events --all-namespaces --sort-by=.lastTimestamp
```

Copy condition text, not secret data.

## Terraform VM Creation

### Image download fails

Verify the URL in a browser or with:

```bash
curl -fsSI URL
```

Then check Proxmox outbound DNS, HTTPS, storage space, and the required import
datastore on every target node.

### VM has no DNS

On the VM:

```bash
ip route
resolvectl status
getent hosts dl.fedoraproject.org
```

Terraform's cloud-init block must provide DNS servers. Fix Terraform and
replace the VM rather than hand-editing a permanent resolver file.

## Ansible Cannot Connect

```bash
ssh-keygen -R "<CONTROL_PLANE_IP>"
ssh -vvv -o IdentitiesOnly=yes \
  -i "$HOME/.ssh/id_ed25519_sk" \
  "<ADMIN_USER>@<CONTROL_PLANE_IP>" true
```

`system-init.yml` reconciles replaced host keys through
`ansible/scripts/reconcile-known-host.sh`.

Check username, public-key injection, YubiKey PIN/touch, TCP 22, cloud-init, and
passwordless sudo.

## DNF5 Appears Hung

On the node:

```bash
ps aux | rg 'dnf|rpm'
systemctl list-jobs
```

The Ansible package-manager role serializes transactions and handles automatic
metadata jobs. Do not add unconditional `dnf5 makecache --refresh`, disable GPG
verification, or kill a transaction without first determining its state.

## CoreDNS Rollout Times Out

Check:

```bash
kubectl get pod --namespace kube-system -o wide
kubectl logs --namespace kube-system \
  --selector k8s-app=kube-dns \
  --tail=100
kubectl get --raw=/readyz
```

CoreDNS needs Pod-to-control-plane TCP `6443`. Confirm the Ansible firewall role
contains the Pod CIDR rule and rerun `system-init.yml` before rerunning cluster
verification.

## Metrics Server Fails TLS

Check:

```bash
kubectl get certificatesigningrequests
kubectl logs --namespace kube-system \
  --selector app.kubernetes.io/name=metrics-server \
  --tail=100
kubectl top nodes
```

The intended solution is:

- `serverTLSBootstrap: true`
- the Ansible kubelet-serving-certificate reconciliation role
- the validated kubelet CSR approver
- Pod-to-kubelet TCP `10250`
- no `--kubelet-insecure-tls`

If the Pods become healthy after the HelmRelease exhausted retries:

```bash
flux reconcile helmrelease metrics-server \
  --namespace kube-system \
  --reset \
  --timeout=10m
```

## Flux Source Is Behind

```bash
kubectl get gitrepository flux-system \
  --namespace flux-system \
  --output jsonpath='{.status.artifact.revision}{"\n"}'
git rev-parse HEAD
```

Then:

```bash
flux reconcile source git flux-system \
  --namespace flux-system \
  --timeout=5m
```

Back-to-back annotations are asynchronous. Use `flux reconcile ... --with-source`
when the ordering of source fetch and Kustomization apply matters.

## Flux Kustomization Waits Forever

```bash
kubectl describe kustomization NAME --namespace flux-system
kubectl get helmreleases --all-namespaces
kubectl get events --all-namespaces --sort-by=.lastTimestamp
```

The condition message normally names the stalled resource. Fix that resource
instead of deleting and recreating the entire Flux installation.

### Clean bootstrap stalls on Grafana credentials

```bash
kubectl describe helmrelease kube-prometheus-stack \
  --namespace monitoring
kubectl get secret grafana-admin-credentials \
  --namespace monitoring
kubectl get externalsecret grafana-admin-credentials \
  --namespace monitoring
kubectl get kustomization infrastructure-controllers infrastructure-configs \
  --namespace flux-system
```

On a clean cluster, a missing `grafana-admin-credentials` Secret can expose the
current stage-ordering problem: Grafana consumes the Secret from
`infrastructure-controllers`, but its ExternalSecret is applied by the
dependent `infrastructure-configs` stage. Correct the dependency ownership in
Git. Do not create an untracked credential Secret just to let Helm continue.

## ExternalSecret Not Found

First distinguish omitted resource from failed synchronization:

```bash
kubectl get externalsecret --all-namespaces
kubectl get kustomization infrastructure-configs --namespace flux-system
kubectl get gitrepository flux-system --namespace flux-system
```

If the resource does not exist, confirm the source revision and Kustomize
`resources:` path. If it exists but is not Ready, inspect the ClusterSecretStore,
Azure identity, vault URL, secret name, and permissions.

## Production ClusterIssuer Is Not Ready

```bash
kubectl get clusterissuer letsencrypt-production \
  --output jsonpath='{range .status.conditions[*]}{.type}{": "}{.reason}{" — "}{.message}{"\n"}{end}'

kubectl get externalsecret \
  --namespace cert-manager \
  cloudflare-api-token letsencrypt-production-account-key
```

Common causes:

- Cloudflare target Secret is absent.
- Persistent ACME account-key target Secret is absent.
- Azure Key Vault reference or permission is wrong.
- Cloudflare token scope is wrong.
- public DNS challenge propagation failed.

Do not generate a new ACME account on every retry. The persistent account key is
part of the rebuild design.

## Ingress Works Only With `-k`

Routing works; certificate validation does not. Check:

```bash
kubectl get certificate --all-namespaces
kubectl get tlsstore --namespace traefik
PUBLIC_HOSTNAME="<PUBLIC_HOSTNAME>"
openssl s_client \
  -connect "${PUBLIC_HOSTNAME}:443" \
  -servername "${PUBLIC_HOSTNAME}" \
  -verify_return_error </dev/null
```

Check hostname coverage, certificate readiness, Traefik TLSStore, system clock,
and Cloudflare origin/proxy mode. Do not make `-k` permanent.

## Longhorn Volume Is Degraded or Detached

```bash
kubectl get nodes.longhorn.io,volumes.longhorn.io \
  --namespace longhorn-system \
  --output wide
kubectl get replicas.longhorn.io,engines.longhorn.io \
  --namespace longhorn-system \
  --output wide
kubectl get persistentvolume,persistentvolumeclaim --all-namespaces
kubectl get events --all-namespaces --sort-by=.lastTimestamp
```

Check node readiness, `iscsid`, the `iscsi_tcp` module, free space under
`/var/lib/longhorn`, replica scheduling, and whether another node is already
being drained. Do not delete a volume, replica, or PVC merely to clear a
condition. Confirm backup status and the `Retain` policy before any destructive
storage action.

## Tailscale Ingress Does Not Resolve or Connect

```bash
kubectl get externalsecret operator-oauth --namespace tailscale
kubectl get helmrelease tailscale-operator --namespace tailscale
kubectl get pods --namespace tailscale
kubectl get proxyclass
kubectl get ingress --all-namespaces
```

Then check the operator logs:

```bash
kubectl logs \
  --namespace tailscale \
  --selector app.kubernetes.io/name=operator \
  --tail=100
```

Confirm the OAuth client is enabled, its permissions and tags match the
operator configuration, the tailnet policy defines those tags, and MagicDNS
and HTTPS certificates are enabled. A private Tailscale hostname should not
have a public DNS record.

## Partial kubeadm or Flux State

The Ansible roles intentionally fail on inconsistent partial state. Inspect it
before deleting anything:

```bash
sudo ls -l /etc/kubernetes /var/lib/kubelet
kubectl get gitrepository,kustomization,secret --namespace flux-system
```

For a disposable VM, deliberate Terraform replacement may be safer than trying
to infer the history of a partially initialized node. Follow the destructive
preflight in the full rebuild procedure.

## Escalation Rule

If a manual command changes durable state:

1. record it
2. determine which owner should enforce it
3. encode it in Terraform, Ansible, or GitOps
4. revert or rebuild the manual state
5. rerun the canonical procedure

A repair is complete only when the automation reproduces it.
