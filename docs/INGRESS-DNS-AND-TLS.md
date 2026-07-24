# Ingress, DNS, and TLS

This document describes the current request path for Grafana and future HTTP applications.

## Addresses and Ports

```text
Control-plane node          192.168.0.52
Traefik LoadBalancer VIP    192.168.0.220
Traefik HTTP NodePort       32492
Traefik HTTPS NodePort      30860
```

Router forwarding:

```text
WAN TCP 80  -> 192.168.0.52 TCP 32492
WAN TCP 443 -> 192.168.0.52 TCP 30860
```

## Why the Router Uses the Master Node

`192.168.0.220` is a MetalLB virtual IP. Kubernetes nodes advertise it on the LAN, but some consumer routers refuse to use an address that is not listed as a normal physical or virtual host.

The router therefore forwards to the static NodePorts on `192.168.0.52`.

Traefik uses:

```yaml
externalTrafficPolicy: Cluster
```

This allows a connection received on the control-plane node to reach a Traefik Pod running elsewhere in the cluster.

## Static NodePorts

The Traefik HelmRelease must pin:

```yaml
ports:
  web:
    nodePort: 32492
  websecure:
    nodePort: 30860
```

Do not depend on automatically allocated NodePorts. Automatic values can change after a Service is recreated, which would break the router configuration.

Verify:

```bash
kubectl get service traefik -n traefik -o yaml
```

Expected fields:

```text
spec.type: LoadBalancer
spec.loadBalancerIP: 192.168.0.220
spec.externalTrafficPolicy: Cluster
web.nodePort: 32492
websecure.nodePort: 30860
```

## Request Paths

### LAN through MetalLB

```text
Client
 -> 192.168.0.220:443
 -> Traefik
 -> Grafana Service
 -> Grafana Pod
```

### Internet through router

```text
Client
 -> public address:443
 -> router port forward
 -> 192.168.0.52:30860
 -> Traefik
 -> Grafana Service
 -> Grafana Pod
```

## Public DNS

`grafana.mccruden.com` must resolve according to the intended ingress design.

For direct router forwarding, the public DNS record should resolve to the router's public address.

Check public DNS:

```bash
dig @1.1.1.1 grafana.mccruden.com A +short
```

On Arch Linux, `dig` is provided by the `bind` package:

```bash
sudo pacman -S bind
```

Check the local resolver:

```bash
resolvectl query grafana.mccruden.com
getent ahostsv4 grafana.mccruden.com
```

## TLS

cert-manager issues the wildcard certificate through the configured ClusterIssuer and Cloudflare DNS-01 credentials.

The certificate proves control of the domain and provides TLS. It does not create the public DNS record and does not configure router port forwarding.

Verify:

```bash
kubectl get clusterissuer
kubectl get certificate -A
kubectl get order,challenge -A
```

## Tests

### Bypass DNS and test MetalLB

```bash
curl -vkI \
  --resolve grafana.mccruden.com:443:192.168.0.220 \
  https://grafana.mccruden.com
```

### Test the static HTTPS NodePort

```bash
curl -vkI \
  --resolve grafana.mccruden.com:30860:192.168.0.52 \
  https://grafana.mccruden.com:30860
```

### Test the normal path

```bash
curl -vkI https://grafana.mccruden.com
```

A working Grafana ingress normally returns an HTTP redirect to `/login`.

## Troubleshooting Order

1. Confirm Grafana Pod and Service health.
2. Confirm the Ingress points to the Grafana Service.
3. Confirm Traefik is Ready.
4. Confirm `192.168.0.220` works with `curl --resolve`.
5. Confirm NodePorts are `32492` and `30860`.
6. Confirm router forwarding targets `192.168.0.52` and the correct ports.
7. Confirm public DNS resolves as intended.
8. Confirm the certificate is Ready.

If the MetalLB test works but the public hostname does not, the problem is outside the Grafana Pod path and is normally DNS, router forwarding, NAT reflection, or Cloudflare proxy behavior.
