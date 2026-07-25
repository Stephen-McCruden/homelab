# Observability

The current platform provides metrics. The next phase adds durable metrics,
centralized logs, external-device syslog, probing, and actionable alerts.

## Current Metrics Stack

Flux deploys:

- Prometheus Operator
- one Prometheus replica
- one Alertmanager replica
- kube-state-metrics
- node-exporter
- standalone Grafana
- Metrics Server
- ServiceMonitors/PodMonitors for supported controllers

Current retention:

```text
Prometheus: 7 days or 8 GB
Storage:    ephemeral
```

Grafana currently provisions Prometheus as its default datasource.

## Current Validation

```bash
kubectl get helmrelease \
  kube-prometheus-stack \
  --namespace monitoring

kubectl get prometheus,alertmanager \
  --namespace monitoring

kubectl get servicemonitor,podmonitor \
  --all-namespaces

kubectl top nodes
curl -fsSI https://grafana.mccruden.com
```

## Target Logging Stack

Use:

- Loki in monolithic mode
- Grafana Alloy as the collector
- Longhorn-backed local storage initially
- an external object store when log survival beyond cluster loss is required

For this lab, distributed Loki would add operational cost without a workload
that justifies it.

## Collection Scope

Alloy DaemonSets should collect:

- Kubernetes container logs
- Kubernetes events
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

Start with:

```text
Kubernetes and host logs: 14 days
Network/security logs:     30 days if capacity permits
```

Measure ingestion and query use before increasing retention. Set hard storage
and query limits so logging cannot evict application workloads.

## Deployment Order

1. Install and prove Longhorn plus external backups.
2. Persist Prometheus, Alertmanager, and Grafana.
3. Install monolithic Loki with a conservative PVC.
4. Provision Loki as a Grafana datasource.
5. Install Alloy for Pod logs and Kubernetes events.
6. Add host journals.
7. Add private TCP syslog ingestion.
8. Add recording rules, alerts, and dashboards.
9. Test loss of one node and restore from backup.

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
