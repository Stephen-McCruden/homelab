# Ingress, DNS, and TLS

This document describes how an HTTP request reaches a workload and how to
isolate failures without disabling TLS verification as a permanent fix.

## Reference Endpoints

| Endpoint | Value |
|---|---|
| Control-plane node | `192.168.0.52` |
| MetalLB pool | `192.168.0.220-192.168.0.229` |
| Traefik VIP | `192.168.0.220` |
| Traefik HTTP NodePort | `32492` |
| Traefik HTTPS NodePort | `30860` |
| Wildcard certificate | `mccruden.com`, `*.mccruden.com` |

Router:

```text
WAN TCP 80  -> 192.168.0.52:32492
WAN TCP 443 -> 192.168.0.52:30860
```

## Request Paths

LAN:

```text
client
  -> 192.168.0.220:443
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
  -> 192.168.0.52:30860
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

## Stable NodePorts

The Traefik HelmRelease pins:

```yaml
ports:
  web:
    nodePort: 32492
  websecure:
    nodePort: 30860
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

Expected VIP: `192.168.0.220`.

## Public DNS

Check authoritative public resolution:

```bash
dig @1.1.1.1 grafana.mccruden.com A +short
dig @1.1.1.1 mccruden.com A +short
```

Check the local resolver:

```bash
resolvectl query grafana.mccruden.com
getent ahostsv4 grafana.mccruden.com
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
  -> wildcard-mccruden-com-tls appears in traefik
  -> Traefik TLSStore uses it as the default certificate
```

Verify in dependency order:

```bash
kubectl get clustersecretstore azure-key-vault
kubectl get externalsecret --all-namespaces
kubectl get clusterissuer
kubectl get certificate wildcard-mccruden-com --namespace traefik
kubectl get order,challenge --all-namespaces
kubectl get tlsstore default --namespace traefik
```

Condition details:

```bash
kubectl get clusterissuer letsencrypt-production \
  --output jsonpath='{range .status.conditions[*]}{.type}{": "}{.reason}{" — "}{.message}{"\n"}{end}'

kubectl get certificate wildcard-mccruden-com \
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
curl -vkI \
  --resolve grafana.mccruden.com:443:192.168.0.220 \
  https://grafana.mccruden.com
```

### 5. Static NodePort

```bash
curl -vkI \
  --resolve grafana.mccruden.com:30860:192.168.0.52 \
  https://grafana.mccruden.com:30860
```

### 6. Public route

```bash
curl -vI https://grafana.mccruden.com
```

If MetalLB works but NodePort does not, inspect the Service, node firewall, and
cluster routing. If NodePort works but the public route does not, inspect the
router, public address, ISP, Cloudflare mode, and DNS.

## TLS Acceptance

Diagnostic commands may use `-k` to prove that routing works while certificate
validation fails. Final acceptance must not:

```bash
curl -fsSI https://grafana.mccruden.com
```

Inspect the presented certificate:

```bash
openssl s_client \
  -connect grafana.mccruden.com:443 \
  -servername grafana.mccruden.com \
  -verify_return_error </dev/null
```

## Adding an Application Hostname

1. Choose whether the application is public, LAN-only, or Tailscale-only.
2. Create the required DNS record in the correct DNS view.
3. Add a Kubernetes Service and Traefik-compatible Ingress.
4. Use `websecure` and enable router TLS.
5. Do not copy the wildcard private key into the application namespace.
6. Let Traefik terminate TLS using the default TLSStore unless isolation
   requires a separate certificate.
7. Add an unauthenticated health endpoint or appropriate probe.
8. Add monitoring before declaring the application complete.
9. Test LAN, NodePort, and normal DNS paths.
10. Require a successful normal TLS request.

Private administrative applications should not become public merely because a
wildcard certificate exists.
