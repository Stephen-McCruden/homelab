# Architecture

This document explains the design that the repository implements. It separates
portable design choices from values that belong only to the reference
environment.

## Design Goals

- Recreate infrastructure and platform state from code.
- Keep credentials outside the public repository.
- Make dependency order explicit instead of relying on timing.
- Make repeated execution safe.
- Preserve normal TLS verification between Metrics Server and kubelets.
- Keep public ingress addresses and router ports stable across rebuilds.
- Provide useful failure isolation at every automation boundary.
- Add persistent data only after an external backup and restore path exists.

## Ownership Boundaries

| Concern | Source of truth | Change mechanism |
|---|---|---|
| Proxmox VMs, CPU, memory, boot disk, NIC, cloud-init | `terraform/` | Terraform plan and apply |
| Fedora packages and node configuration | `ansible/playbooks/system-init.yml` | Ansible |
| kubeadm, worker joins, Cilium, kubelet TLS | `ansible/playbooks/cluster-bootstrap.yml` | Ansible |
| Flux bootstrap and SOPS bootstrap Secret | `ansible/playbooks/platform-bootstrap.yml` | Ansible |
| Kubernetes controllers and applications | `clusters/` and `kubernetes/` | Git commit, push, and Flux |
| Runtime secret values | Azure Key Vault | External Secrets Operator |
| Encrypted Azure bootstrap identity | SOPS-encrypted manifest in Git | SOPS |
| Public DNS | Cloudflare | External administration |
| WAN port forwarding | Router or firewall | External administration |
| Terraform state | HCP Terraform workspace | Terraform |

Do not use two owners for the same object. In particular:

- Do not install a Flux-managed Helm chart manually.
- Do not edit a Terraform-managed VM in Proxmox and assume the change is
  durable.
- Do not edit an Ansible-managed node file without updating its role.
- Do not edit an ExternalSecret target Secret directly.

## Reference Topology

```text
LAN: 192.168.0.0/24
Gateway and DNS: 192.168.0.1

pve1
└─ k8s-worker-01  192.168.0.50/24  4 vCPU  8 GiB

pve2
└─ k8s-worker-02  192.168.0.51/24  4 vCPU  8 GiB

pve3
└─ k8s-master-01  192.168.0.52/24  4 vCPU  8 GiB

Kubernetes Pod CIDR:      10.244.0.0/16
Kubernetes Service CIDR:  10.96.0.0/12
MetalLB pool:             192.168.0.220-192.168.0.229
Traefik address:          192.168.0.220
```

The control-plane endpoint is currently the control-plane node address:

```text
192.168.0.52:6443
```

This makes the control plane a single failure domain. A later HA design needs a
stable virtual endpoint, three control-plane members, and an etcd recovery
procedure.

## Bootstrap Sequence

```text
Existing external services
  ├─ Proxmox
  ├─ HCP Terraform
  ├─ GitHub
  ├─ Azure Key Vault
  ├─ Cloudflare DNS
  └─ Router
       |
       v
Terraform creates Fedora VMs
       |
       v
Ansible converges Fedora nodes
       |
       v
Ansible runs kubeadm and installs Cilium
       |
       v
Ansible reconciles secure kubelet serving certificates
       |
       v
Ansible provisions flux-system/sops-age and bootstraps Flux
       |
       v
Flux reconciles controllers, configuration, and applications
```

Ansible creates only the bootstrap Secret that Flux needs to decrypt the
repository. External Secrets then restores runtime Secrets from Azure Key Vault.

## Flux Dependency Graph

The repository deliberately has two branches:

```text
flux-system
├─ infrastructure-controllers
│  └─ infrastructure-configs
│     └─ applications
└─ infrastructure-kubelet-csr-approver
   └─ infrastructure-metrics-server
```

The application-critical branch contains:

- cert-manager
- External Secrets Operator
- kube-prometheus-stack
- MetalLB
- Traefik
- runtime secret synchronization
- ACME issuers and wildcard certificate
- Grafana

The node-metrics branch exists because secure kubelet serving certificates have
a bootstrap dependency:

1. kubeadm configures kubelets to request serving certificates.
2. kubelets create CSRs.
3. the approver validates node identity, address range, and DNS names.
4. approved certificates are issued.
5. Metrics Server connects to kubelets with normal TLS verification.

A failure in Metrics Server must be visible, but it must not prevent External
Secrets, TLS, ingress, and normal applications from reconciling.

## Network Model

### Node and Pod traffic

Fedora firewalld remains enabled. Ansible creates explicit rules for:

- control-plane components
- kubelet HTTPS on TCP `10250`
- Cilium VXLAN on UDP `8472`
- Cilium health traffic on TCP `4240`
- the Kubernetes API on TCP `6443`
- required node monitoring ports
- Pod-to-API and Pod-to-kubelet traffic

The full NodePort range is disabled by default. Traefik's required NodePorts are
declared by its Service and reached through the expected cluster networking
path.

### Ingress

LAN path:

```text
client -> 192.168.0.220:443 -> Traefik -> Service -> Pod
```

Internet path:

```text
client
  -> public DNS
  -> router TCP 443
  -> 192.168.0.52:30860
  -> Traefik
  -> Service
  -> Pod
```

The router targets a static node address because it cannot use the MetalLB
virtual address as a port-forward destination. Traefik uses
`externalTrafficPolicy: Cluster`, so a request arriving on the control-plane
NodePort can reach a Traefik replica on another node.

See [Ingress, DNS, and TLS](INGRESS-DNS-AND-TLS.md).

## Secret Flow

```text
Offline SOPS age identity
  -> decrypts Azure bootstrap credential in Git
  -> Flux applies Azure bootstrap Secret
  -> ClusterSecretStore authenticates to Azure Key Vault
  -> ExternalSecrets create runtime Kubernetes Secrets
```

Current Azure Key Vault values:

- `cloudflare-api-token`
- `grafana-admin-user`
- `grafana-admin-password`
- `letsencrypt-production-account-key`

The Let's Encrypt production account key is persistent so rebuilding the
cluster does not register a new ACME account each time.

## Data Durability

Current state:

| Data | Durability |
|---|---|
| Terraform state | HCP Terraform |
| GitOps desired state | GitHub |
| Runtime secret source | Azure Key Vault |
| SOPS recovery identity | Operator-controlled offline copy |
| Kubernetes etcd | Single control-plane VM only |
| Prometheus data | Ephemeral |
| Alertmanager data | Ephemeral |
| Grafana data | Ephemeral |
| Application PVC data | Not implemented |

Longhorn replication will improve node-level availability, but it will not
replace backup. The target design uses dedicated disks on every VM and an
external backup target. See [Storage and backups](STORAGE-AND-BACKUPS.md).

## Failure Domains

| Failure | Expected effect | Recovery source |
|---|---|---|
| One worker VM | Workloads reschedule if replicas and storage permit | Terraform, Ansible, Flux |
| Control-plane VM | Kubernetes API and etcd unavailable | Rebuild procedure; future etcd backup |
| One Proxmox node | Its VM is unavailable | Proxmox HA if configured, or Terraform |
| Complete Kubernetes cluster | All in-cluster applications unavailable | Terraform, Ansible, Flux, external backups |
| GitHub unavailable | Existing workloads continue; reconciliation stops | Existing cluster state; repository backup |
| Azure Key Vault unavailable | Existing Secrets remain; refresh and new rebuild fail | Azure recovery and secret inventory |
| Home power or WAN outage | Public applications unavailable | UPS for short events; no off-site serving |

## Reproducing in Another Environment

At minimum, change:

- HCP organization and workspace in `terraform/main.tf`
- Proxmox API, storage IDs, bridge, nodes, VM IDs, and image source
- node addresses, gateway, DNS servers, and SSH keys
- Ansible inventory, management networks, usernames, and kubeconfig path
- kubeadm control-plane endpoint and network CIDRs
- kubelet CSR approver node-name regex and address prefixes
- MetalLB pool and Traefik address
- domain, ACME email, Cloudflare references, and ingress hostnames
- Azure tenant, vault URL, service principal, and secret names
- Flux GitHub owner, repository, branch, and cluster path
- router forwarding and public DNS

Search for reference-environment values before deploying:

```bash
rg -n \
  'Stephen-McCruden|mccruden\.com|192\.168\.0|stoof|kvhomelab|pve[123]' \
  --glob '!**/.git/**'
```

Every remaining match must either be replaced or intentionally retained.
