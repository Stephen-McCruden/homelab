# Ingress, DNS, and TLS

This document describes how an HTTP request reaches a workload and how to
isolate failures without disabling TLS verification as a permanent fix.

## Deployment Values

| Endpoint | Value |
|---|---|
| Control-plane node | `<CONTROL_PLANE_IP>` |
| MetalLB pool | `<METALLB_RANGE>` |
| Traefik VIP | `<TRAEFIK_VIP>` |
| Traefik HTTP NodePort | `<TRAEFIK_HTTP_NODEPORT>` |
| Traefik HTTPS NodePort | `<TRAEFIK_HTTPS_NODEPORT>` |
| Wildcard certificate | `<PUBLIC_DOMAIN>`, `*.<PUBLIC_DOMAIN>` |
| Tailnet domain | `<TAILNET_DOMAIN>` |

Router:

```text
WAN TCP 80  -> <CONTROL_PLANE_IP>:<TRAEFIK_HTTP_NODEPORT>
WAN TCP 443 -> <CONTROL_PLANE_IP>:<TRAEFIK_HTTPS_NODEPORT>
```

## Request Paths

LAN:

```text
client
  -> <TRAEFIK_VIP>:443
  -> Traefik websecure entrypoint
  -> Kubernetes Service
  -> application Pod
```

Internet:

```text
client
  -> Cloudflare DNS
  -> home public address
  -> router
  -> <CONTROL_PLANE_IP>:<TRAEFIK_HTTPS_NODEPORT>
  -> Traefik
  -> Kubernetes Service
  -> application Pod
```

The router targets the control-plane node because it cannot select the MetalLB
virtual address as a port-forward destination. Traefik uses:

```yaml
externalTrafficPolicy: Cluster
```

Traffic received on that node can therefore reach a Traefik replica elsewhere.

Tailscale-private:

```text
tailnet client
  -> <SERVICE>.<TAILNET_DOMAIN>
  -> Tailscale ingress proxy
  -> Kubernetes Service
  -> application Pod
```

Homepage, Linkding, Mealie, FreshRSS, and Grafana have private Ingress
resources with `ingressClassName: tailscale`. Tailscale supplies MagicDNS
records and HTTPS certificates; no public DNS record or router forwarding is
needed.

## Stable NodePorts

The Traefik HelmRelease pins:

```yaml
ports:
  web:
    nodePort: <TRAEFIK_HTTP_NODEPORT>
  websecure:
    nodePort: <TRAEFIK_HTTPS_NODEPORT>
```

Verify:

```bash
kubectl get service traefik \
  --namespace traefik \
  --output jsonpath='{range .spec.ports[*]}{.name}{" "}{.port}{" "}{.nodePort}{"\n"}{end}'

kubectl get service traefik \
  --namespace traefik \
  --output jsonpath='{.status.loadBalancer.ingress[0].ip}{"\n"}'
```

The reported address must match the configured Traefik VIP.

## Public DNS

Check authoritative public resolution:

```bash
PUBLIC_HOSTNAME="<PUBLIC_HOSTNAME>"

dig @1.1.1.1 "$PUBLIC_HOSTNAME" A +short
```

Check the local resolver:

```bash
resolvectl query "$PUBLIC_HOSTNAME"
getent ahostsv4 "$PUBLIC_HOSTNAME"
```

Inside the LAN, use either NAT reflection or split DNS. A local failure with a
working external test may be a hairpin NAT issue rather than a Kubernetes issue.

## Certificate Flow

```text
SOPS decrypts Azure bootstrap credentials
  -> External Secrets authenticates to Azure Key Vault
  -> cloudflare-api-token Secret appears in cert-manager
  -> persistent production ACME account key appears
  -> ClusterIssuer becomes Ready
  -> cert-manager completes Cloudflare DNS-01
  -> wildcard certificate Secret appears in traefik
  -> Traefik TLSStore uses it as the default certificate
```

Verify in dependency order:

```bash
kubectl get clustersecretstore azure-key-vault
kubectl get externalsecret --all-namespaces
kubectl get clusterissuer
kubectl get certificate --namespace traefik
kubectl get order,challenge --all-namespaces
kubectl get tlsstore default --namespace traefik
```

Condition details:

```bash
kubectl get clusterissuer letsencrypt-production \
  --output jsonpath='{range .status.conditions[*]}{.type}{": "}{.reason}{" — "}{.message}{"\n"}{end}'

kubectl get certificate "<WILDCARD_CERTIFICATE_NAME>" \
  --namespace traefik \
  --output jsonpath='{range .status.conditions[*]}{.type}{": "}{.reason}{" — "}{.message}{"\n"}{end}'
```

Do not delete a production ACME account Secret to force a retry. The account key
is deliberately restored from Azure to survive rebuilds.

## Route Isolation

### 1. Application

```bash
kubectl get pod,service,ingress --namespace monitoring
kubectl get endpointslice --namespace monitoring \
  --selector kubernetes.io/service-name=grafana
```

### 2. Traefik

```bash
kubectl get pod,service --namespace traefik
kubectl logs \
  --namespace traefik \
  --selector app.kubernetes.io/name=traefik \
  --tail=100
```

### 3. MetalLB

```bash
kubectl get ipaddresspool,l2advertisement --namespace metallb-system
kubectl get pod --namespace metallb-system
```

### 4. LAN route

```bash
PUBLIC_HOSTNAME="<PUBLIC_HOSTNAME>"
TRAEFIK_VIP="<TRAEFIK_VIP>"

curl -vkI \
  --resolve "${PUBLIC_HOSTNAME}:443:${TRAEFIK_VIP}" \
  "https://${PUBLIC_HOSTNAME}"
```

### 5. Static NodePort

```bash
CONTROL_PLANE_IP="<CONTROL_PLANE_IP>"
TRAEFIK_HTTPS_NODEPORT="<TRAEFIK_HTTPS_NODEPORT>"

curl -vkI \
  --resolve \
    "${PUBLIC_HOSTNAME}:${TRAEFIK_HTTPS_NODEPORT}:${CONTROL_PLANE_IP}" \
  "https://${PUBLIC_HOSTNAME}:${TRAEFIK_HTTPS_NODEPORT}"
```

### 6. Public route

```bash
curl -vI "https://${PUBLIC_HOSTNAME}"
```

If MetalLB works but NodePort does not, inspect the Service, node firewall, and
cluster routing. If NodePort works but the public route does not, inspect the
router, public address, ISP, Cloudflare mode, and DNS.

### 7. Tailscale-private route

```bash
TAILNET_DOMAIN="<TAILNET_DOMAIN>"

kubectl get ingress --all-namespaces \
  --output custom-columns='NAMESPACE:.metadata.namespace,NAME:.metadata.name,CLASS:.spec.ingressClassName,HOST:.status.loadBalancer.ingress[0].hostname'
kubectl get statefulset,pod --all-namespaces | rg 'tailscale|ts-'
curl -fsSI "https://homepage.${TAILNET_DOMAIN}"
curl -fsSI "https://linkding.${TAILNET_DOMAIN}"
curl -fsSI "https://mealie.${TAILNET_DOMAIN}"
curl -fsSI "https://freshrss.${TAILNET_DOMAIN}"
curl -fsSI "https://grafana.${TAILNET_DOMAIN}"
```

If the Ingress exists but its hostname is unavailable, inspect the Tailscale
Operator, `operator-oauth` ExternalSecret, OAuth permissions, ACL tags,
MagicDNS, and HTTPS-certificate settings.

## TLS Acceptance

Diagnostic commands may use `-k` to prove that routing works while certificate
validation fails. Final acceptance must not:

```bash
curl -fsSI "https://${PUBLIC_HOSTNAME}"
```

Inspect the presented certificate:

```bash
openssl s_client \
  -connect "${PUBLIC_HOSTNAME}:443" \
  -servername "${PUBLIC_HOSTNAME}" \
  -verify_return_error </dev/null
```

## Adding an Application Hostname

1. Choose whether the application is public, LAN-only, or Tailscale-only.
2. For a public application, create the required public DNS record and a
   Traefik Ingress. For a private application, create a Tailscale Ingress and
   do not create public DNS.
3. Add a Kubernetes Service and the selected Ingress.
4. For Traefik, use `websecure` and enable router TLS.
5. Do not copy the wildcard private key into the application namespace.
6. Let Traefik terminate public TLS using the default TLSStore unless isolation
   requires a separate certificate.
7. Add an unauthenticated health endpoint or appropriate probe.
8. Add monitoring before declaring the application complete.
9. Test LAN, NodePort, and normal DNS paths.
10. Require a successful normal TLS request.

Private administrative applications should not become public merely because a
wildcard certificate exists.
