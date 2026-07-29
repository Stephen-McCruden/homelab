# Observability

The platform provides durable metrics, dashboards, Kubernetes logs, and
Kubernetes events. Prometheus, Alertmanager, Grafana, Loki, and Alloy are
managed through Flux.

## Current Stack

Flux deploys:

- Prometheus Operator
- one Prometheus replica
- one Alertmanager replica
- kube-state-metrics
- node-exporter
- standalone Grafana
- single-binary Loki
- one Grafana Alloy collector
- Metrics Server
- ServiceMonitors/PodMonitors for supported controllers

Current storage and retention:

| Component | Longhorn claim | Retention |
|---|---:|---:|
| Prometheus | 30 GiB | 15 days, capped at 25 GB |
| Alertmanager | 2 GiB | Operational state |
| Grafana | 5 GiB | Dashboards and UI-managed settings |
| Loki | 30 GiB | 14 days |
| Alloy | 1 GiB | Collector positions and runtime state |

Grafana provisions Prometheus as its default datasource and Loki as its log
datasource. The kube-prometheus-stack chart creates the dashboard ConfigMaps;
standalone Grafana discovers them with its dashboard sidecar.

Alloy uses the Kubernetes API to collect:

- Pod container logs from every namespace
- Kubernetes events from every namespace

The API-based collector avoids privileged containers and host filesystem
mounts. Host journals and appliance syslog are separate later additions.

## Current Validation

```bash
kubectl get helmrelease \
  --namespace monitoring

kubectl get prometheus,alertmanager \
  --namespace monitoring

kubectl get pods,persistentvolumeclaim \
  --namespace monitoring

kubectl get servicemonitor,podmonitor \
  --all-namespaces

kubectl top nodes

kubectl port-forward \
  --namespace monitoring \
  service/loki \
  3100:3100

curl -fsS http://127.0.0.1:3100/ready

TAILNET_DOMAIN="<TAILNET_DOMAIN>"
curl -fsSI "https://grafana.${TAILNET_DOMAIN}"
```

Grafana currently retains both a Traefik route and a private Tailscale route.
Remove the public route only after the private path and operator recovery
procedure are proven.

Check Loki ingestion in Grafana Explore with:

```logql
{cluster="homelab", source="kubernetes-pods"}
{cluster="homelab", source="kubernetes-events"}
```

Single-binary Loki is appropriate for this lab. Distributed Loki would add
operational cost without a workload that justifies it.

## Next Collection Scope

Add host-level collection only after the current Kubernetes log path is stable:

- kubelet journal
- containerd journal
- firewalld journal
- selected Fedora system journals

Later, receive syslog from:

- OPNsense
- Proxmox nodes
- managed switch
- UPS/NUT systems
- other network appliances

Prefer TCP syslog where the sender supports it. Keep the listener private and
restrict allowed source networks.

## Label Policy

Low-cardinality labels:

```text
cluster
namespace
workload
container
node
source
facility
severity
```

Do not index unbounded values such as request IDs, full URLs, client IPs, user
IDs, or arbitrary message content as labels. Keep them in the log body or
structured metadata.

## Retention

Current retention:

```text
Kubernetes and host logs: 14 days
Network/security logs:     30 days if capacity permits
```

Measure ingestion and query use before increasing retention. Set hard storage
and query limits so logging cannot evict application workloads.

## Next Work

1. Verify Prometheus, Grafana, and Loki data after Pod deletion and
   rescheduling.
2. Configure an off-cluster backup target and test restoration.
3. Add host journals, then private TCP syslog ingestion.
4. Add recording rules, alerts, and dashboards.
5. Add private syslog ingestion for network and power equipment.

## Additional Monitoring

Recommended next components:

| Component | Purpose | Priority |
|---|---|---:|
| Blackbox Exporter | HTTPS, DNS, TCP, and certificate probes | High |
| Proxmox exporter | Hypervisor and VM capacity | High |
| SNMP exporter | Switch and OPNsense metrics | High |
| NUT exporter | UPS state and runtime | High |
| Alertmanager receiver | Deliver actionable alerts | High |
| Tempo | Distributed traces | Later |

Do not add tracing until applications emit useful trace context.

## Initial SLOs

Suggested first service-level indicators:

- public website successful HTTPS probe
- Grafana successful HTTPS probe
- Kubernetes API readiness
- all Flux Kustomizations Ready
- all HelmReleases Ready
- node Ready count
- certificate days until expiry
- ExternalSecret Ready state
- Longhorn volume robustness
- backup age

Begin with realistic objectives and measure them:

```text
Public website monthly availability: 99.5%
GitOps reconciliation freshness:      under 15 minutes
Critical backup age:                  under 24 hours
Certificate remaining lifetime:       over 14 days
```

Planned maintenance and full rebuilds affect a self-hosted public website.
Report that honestly rather than selecting an objective the architecture cannot
support.

## Alert Quality

Every alert must answer:

- what user-visible behavior is at risk
- which runbook to open
- what evidence triggered it
- when it should page versus create a low-priority notification

Avoid alerts for conditions that self-heal within normal reconciliation time.

## References

- [Grafana Loki overview](https://grafana.com/docs/loki/latest/get-started/overview/)
- [Install Loki with Helm](https://grafana.com/docs/loki/latest/setup/install/helm/)
- [Send logs with Grafana Alloy](https://grafana.com/docs/loki/latest/send-data/)
- [Loki label guidance](https://grafana.com/docs/loki/latest/get-started/labels/)
