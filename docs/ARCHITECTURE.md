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
- Keep replicated storage, off-cluster backup, and restore responsibilities
  explicit.

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
| Private service DNS and HTTPS | Tailscale | Tailscale Operator and external administration |
| Public DNS | Cloudflare | External administration |
| WAN port forwarding | Router or firewall | External administration |
| Terraform state | HCP Terraform workspace | Terraform |

Do not use two owners for the same object. In particular:

- Do not install a Flux-managed Helm chart manually.
- Do not edit a Terraform-managed VM in Proxmox and assume the change is
  durable.
- Do not edit an Ansible-managed node file without updating its role.
- Do not edit an ExternalSecret target Secret directly.

## Example Topology

```text
LAN: <LAN_CIDR>
Gateway and DNS: <GATEWAY_IP>

<PROXMOX_NODE_1>
└─ k8s-worker-01  <WORKER_1_CIDR>  <CPU>  <MEMORY>

<PROXMOX_NODE_2>
└─ k8s-worker-02  <WORKER_2_CIDR>  <CPU>  <MEMORY>

<PROXMOX_NODE_3>
└─ k8s-master-01  <CONTROL_PLANE_CIDR>  <CPU>  <MEMORY>

Kubernetes Pod CIDR:      10.244.0.0/16
Kubernetes Service CIDR:  10.96.0.0/12
MetalLB pool:             <METALLB_RANGE>
Traefik address:          <TRAEFIK_VIP>
```

The included design uses the control-plane node address directly:

```text
<CONTROL_PLANE_IP>:6443
```

This makes the control plane a single failure domain. A later HA design needs a
stable virtual endpoint, three control-plane members, and an etcd recovery
procedure. The example CPU, memory, storage, and network values in the tracked
Terraform and Ansible files must be reviewed before deployment; they are not
requirements of the design.

## Bootstrap Sequence

```text
Existing external services
  ├─ Proxmox
  ├─ HCP Terraform
  ├─ GitHub
  ├─ Azure Key Vault
  ├─ Cloudflare DNS
  ├─ Tailscale
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
│     └─ infrastructure-tailscale-operator
│        └─ infrastructure-tailscale-ingress
│           └─ applications
│              └─ website image automation
└─ infrastructure-kubelet-csr-approver
   └─ infrastructure-metrics-server
```

The application-critical branch contains:

- cert-manager
- External Secrets Operator
- kube-prometheus-stack
- Longhorn
- MetalLB
- Traefik
- runtime secret synchronization
- ACME issuers and wildcard certificate
- Tailscale private ingress
- Grafana, Homepage, Linkding, Mealie, FreshRSS, and the public website

The node-metrics branch exists because secure kubelet serving certificates have
a bootstrap dependency:

1. kubeadm configures kubelets to request serving certificates.
2. kubelets create CSRs.
3. the approver validates node identity, address range, and DNS names.
4. approved certificates are issued.
5. Metrics Server connects to kubelets with normal TLS verification.

A failure in Metrics Server must be visible, but it must not prevent External
Secrets, TLS, ingress, and normal applications from reconciling.

### Clean-bootstrap caveat

The bundled Grafana release references `grafana-admin-credentials` from the
controller stage, while the ExternalSecret that creates it is applied in
`infrastructure-configs`. An existing cluster can already have that Secret, but
a clean cluster may stall before the configuration stage is allowed to run.
The rebuild proof must either demonstrate that this ordering succeeds or move
the credential-producing resource or Grafana release to a dependency-safe
stage. Do not solve this with an undocumented manually created Secret.

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
client -> <TRAEFIK_VIP>:443 -> Traefik -> Service -> Pod
```

Internet path:

```text
client
  -> public DNS
  -> router TCP 443
  -> <CONTROL_PLANE_IP>:<TRAEFIK_HTTPS_NODEPORT>
  -> Traefik
  -> Service
  -> Pod
```

The router targets a static node address because it cannot use the MetalLB
virtual address as a port-forward destination. Traefik uses
`externalTrafficPolicy: Cluster`, so a request arriving on the control-plane
NodePort can reach a Traefik replica on another node.

Private path:

```text
tailnet client
  -> <SERVICE>.<TAILNET_DOMAIN>
  -> Tailscale ingress proxy
  -> Kubernetes Service
  -> Pod
```

The private path does not require router port forwarding or public DNS.

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
- `linkding-superuser-name`
- `linkding-superuser-password`
- `freshrss-admin-email`
- `freshrss-admin-password`
- `freshrss-api-password`
- `tailscale-operator-client-id`
- `tailscale-operator-client-secret`

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
| Linkding data | 5 GiB Longhorn PVC, two replicas |
| Mealie data | 10 GiB Longhorn PVC, two replicas |
| FreshRSS data | 5 GiB Longhorn PVC, two replicas |
| Homepage and website | Stateless and reproducible from Git |

Longhorn is installed with two replicas and a `Retain` reclaim policy. It
currently uses `/var/lib/longhorn` on each VM root filesystem. This improves
node-level availability, but it does not survive complete VM destruction and
does not replace backup. The next storage step is an external backup target
with a tested restore. See [Storage and backups](STORAGE-AND-BACKUPS.md).

## Failure Domains

| Failure | Expected effect | Recovery source |
|---|---|---|
| One worker VM | Workloads reschedule if replicas and healthy Longhorn copies permit | Terraform, Ansible, Flux, Longhorn replicas |
| Control-plane VM | Kubernetes API and etcd unavailable | Rebuild procedure; future etcd backup |
| One Proxmox node | Its VM is unavailable | Proxmox HA if configured, or Terraform |
| Complete Kubernetes cluster | All in-cluster applications unavailable | Terraform, Ansible, Flux, external backups |
| GitHub unavailable | Existing workloads continue; reconciliation stops | Existing cluster state; repository backup |
| Azure Key Vault unavailable | Existing Secrets remain; refresh and new rebuild fail | Azure recovery and secret inventory |
| Tailscale unavailable | Private endpoints fail; public Traefik routes are unaffected | Tailscale administration and GitOps |
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
- Tailscale OAuth client, ACL tags, tailnet domain, and private hostnames
- Homepage links, labels, and external URLs
- router forwarding and public DNS

Search for reference-environment values before deploying:

```bash
rg -n \
  'REPLACE|YOUR_|<[^>]+>|example\.com|example\.ts\.net' \
  --glob '!**/.git/**'
```

Every remaining match must either be replaced or intentionally retained.
