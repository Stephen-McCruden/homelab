# Operations

This is the normal operator reference after deployment. It does not replace the
full rebuild runbook.

## Load Cluster Access

```bash
export KUBECONFIG="$HOME/.kube/homelab-admin.conf"
kubectl cluster-info
```

## Quick Health Check

```bash
kubectl get nodes
kubectl get pods --all-namespaces
kubectl get kustomizations --namespace flux-system
kubectl get helmreleases --all-namespaces
kubectl top nodes
kubectl get clusterissuer
kubectl get certificate --all-namespaces
kubectl get clustersecretstore
kubectl get externalsecret --all-namespaces
kubectl get persistentvolumeclaim --all-namespaces
kubectl get nodes.longhorn.io,volumes.longhorn.io \
  --namespace longhorn-system
kubectl get ingress --all-namespaces
```

Use Ready conditions and events, not Pod phase alone. A running Pod can belong
to a failed HelmRelease, and a healthy workload does not automatically clear an
exhausted Helm remediation counter.

## Flux Failure Isolation

Read the graph from the first unready Kustomization:

```bash
kubectl get kustomizations \
  --namespace flux-system \
  --output wide

kubectl describe kustomization NAME \
  --namespace flux-system
```

Then inspect the HelmRelease or Kubernetes object named in the condition:

```bash
kubectl get helmreleases --all-namespaces
kubectl describe helmrelease NAME --namespace NAMESPACE
kubectl get events --all-namespaces --sort-by=.lastTimestamp
```

Do not reconcile every dependency repeatedly. Fix the first real failure.

### Synchronous source reconciliation

When the Git source has not fetched the pushed commit:

```bash
flux reconcile source git flux-system \
  --namespace flux-system \
  --timeout=5m

flux reconcile kustomization NAME \
  --namespace flux-system \
  --with-source \
  --timeout=10m
```

Confirm the applied revision:

```bash
kubectl get gitrepository flux-system \
  --namespace flux-system \
  --output jsonpath='{.status.artifact.revision}{"\n"}'
```

### Exhausted Helm remediation

If the underlying problem is fixed but the HelmRelease retains a failed retry
state:

```bash
flux reconcile helmrelease NAME \
  --namespace NAMESPACE \
  --reset \
  --timeout=10m
```

Use `--reset` only after verifying the original cause is gone.

## External Secrets

```bash
kubectl get clustersecretstore
kubectl get externalsecret --all-namespaces
```

Force one refresh:

```bash
kubectl annotate externalsecret NAME \
  --namespace NAMESPACE \
  force-sync="$(date +%s)" \
  --overwrite

kubectl wait externalsecret NAME \
  --namespace NAMESPACE \
  --for=condition=Ready \
  --timeout=2m
```

Inspect conditions, not values:

```bash
kubectl describe externalsecret NAME --namespace NAMESPACE
```

## Kubelet Certificates and Metrics

```bash
kubectl get certificatesigningrequests \
  --output custom-columns='NAME:.metadata.name,SIGNER:.spec.signerName,REQUESTOR:.spec.username,CONDITIONS:.status.conditions[*].type'

kubectl get helmrelease metrics-server --namespace kube-system
kubectl get pods --namespace kube-system \
  --selector app.kubernetes.io/name=metrics-server
kubectl top nodes
```

Never approve an unknown CSR simply to make Metrics Server work. Validate the
requestor, signer, node name, and requested addresses.

## Certificate Operations

```bash
kubectl get clusterissuer
kubectl get certificate,certificaterequest,order,challenge --all-namespaces
```

Read conditions:

```bash
kubectl describe clusterissuer letsencrypt-production
kubectl describe certificate "<WILDCARD_CERTIFICATE_NAME>" \
  --namespace traefik
```

Do not delete ACME account keys during routine troubleshooting.

## Longhorn

```bash
kubectl get helmrelease longhorn --namespace longhorn-system
kubectl get pods --namespace longhorn-system
kubectl get nodes.longhorn.io \
  --namespace longhorn-system \
  --output wide
kubectl get volumes.longhorn.io \
  --namespace longhorn-system \
  --output wide
kubectl get persistentvolumeclaim --all-namespaces
```

Every attached volume should report `robustness: healthy`. Investigate degraded
replicas, scheduling failures, low free space, or unexpected detachments before
draining another node. A healthy replica count is not proof of an independent
backup.

## Tailscale Private Access

```bash
kubectl get externalsecret operator-oauth --namespace tailscale
kubectl get helmrelease tailscale-operator --namespace tailscale
kubectl get pods --namespace tailscale
kubectl get proxyclass
kubectl get ingress --all-namespaces
```

Acceptance from a tailnet-connected client:

```bash
TAILNET_DOMAIN="<TAILNET_DOMAIN>"
curl -fsSI "https://homepage.${TAILNET_DOMAIN}"
curl -fsSI "https://linkding.${TAILNET_DOMAIN}"
curl -fsSI "https://mealie.${TAILNET_DOMAIN}"
curl -fsSI "https://freshrss.${TAILNET_DOMAIN}"
curl -fsSI "https://grafana.${TAILNET_DOMAIN}"
```

## Normal GitOps Change

1. Change the manifest in Git.
2. Build its Kustomize root locally.
3. Review `git diff`.
4. Commit and push.
5. Watch the affected Flux Kustomization.
6. Verify the workload and its user-visible behavior.
7. Record any operational change in documentation.

Manual `kubectl edit`, `kubectl patch`, and Helm CLI changes are temporary
diagnostic mutations. Flux may revert them, and they are lost during rebuild.

## Node Maintenance

Before planned worker maintenance:

```bash
kubectl cordon NODE
kubectl get volumes.longhorn.io \
  --namespace longhorn-system \
  --output wide
kubectl drain NODE \
  --ignore-daemonsets \
  --delete-emptydir-data
```

After maintenance:

```bash
kubectl uncordon NODE
kubectl get nodes
kubectl get pods --all-namespaces --field-selector spec.nodeName=NODE
```

The single control-plane node requires a planned control-plane outage. Do not
assume draining it creates HA.

## Update Policy

- Terraform provider, Fedora image, Kubernetes, Cilium, Flux, and Helm chart
  versions are deliberate changes.
- Read upstream release notes.
- Change one platform layer at a time.
- Validate in Git, then test the affected runbook.
- Run Ansible twice after role changes.
- Preserve a known-good Git tag before a major upgrade.

Avoid unbounded version constraints in a reproducibility-focused repository.

## Monthly Recovery Check

- confirm HCP state is accessible
- confirm both offline SOPS identities can decrypt the test manifest
- confirm Azure secret names and enabled state
- confirm the Tailscale OAuth client and ACL tags are recoverable
- confirm the GitHub repository has an independent backup or mirror
- confirm Terraform variables and public SSH keys are recoverable
- confirm public DNS and router rules match documentation
- confirm application backup jobs succeeded
- perform at least one restore test, not only a backup job check

## Incident Notes

For every material failure, record:

- timestamp and user-visible impact
- affected layer
- first failing condition
- evidence collected
- temporary mitigation
- permanent code or prerequisite change
- validation
- prevention or detection improvement

The best portfolio artifact is not a perfect uptime claim; it is a clear,
evidence-backed incident review showing that the system improved.
