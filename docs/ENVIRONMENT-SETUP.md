# Environment Setup

This document lists everything that must exist outside the repository before a
first deployment or a full rebuild. It is a prerequisite checklist, not an
installation guide for Proxmox, Cloudflare, Azure, GitHub, or HCP Terraform.

## External Dependency Inventory

| Dependency | Used for | Required during rebuild |
|---|---|---:|
| Three-node Proxmox VE cluster | VM compute and storage | Yes |
| LAN gateway and DNS | Node routing and name resolution | Yes |
| Router or firewall | Public TCP 80/443 forwarding | For public access |
| HCP Terraform | Terraform state | Yes |
| GitHub repository | Desired state and Flux bootstrap | Yes |
| Cloudflare DNS | Public records and ACME DNS-01 | Yes |
| Azure Key Vault | Runtime secret recovery | Yes |
| Tailscale | Private service DNS and HTTPS | For private access |
| SOPS age identity | Decrypt Azure bootstrap credential | Yes |
| Operator SSH key | Ansible access | Yes |
| Short-lived GitHub token | First Flux bootstrap | Yes |

Record provider account recovery and MFA information separately from this
public repository.

## Values to Choose

```text
LAN CIDR                  <LAN_CIDR>
Gateway and primary DNS   <GATEWAY_IP>
Secondary DNS             <SECONDARY_DNS_IP>

k8s-worker-01             <WORKER_1_CIDR>
k8s-worker-02             <WORKER_2_CIDR>
k8s-master-01             <CONTROL_PLANE_CIDR>

MetalLB pool              <METALLB_RANGE>
Traefik VIP               <TRAEFIK_VIP>
Traefik HTTP NodePort     <TRAEFIK_HTTP_NODEPORT>
Traefik HTTPS NodePort    <TRAEFIK_HTTPS_NODEPORT>
Public domain             <PUBLIC_DOMAIN>
Tailnet domain            <TAILNET_DOMAIN>
```

Reserve node and MetalLB addresses outside the DHCP pool.

## Proxmox

Before Terraform runs, confirm:

- the Proxmox cluster has quorum
- all Proxmox nodes named in `k8s_nodes` are online
- the configured import datastore exists on every target node
- the VM datastore exists on every target node
- the configured Linux bridge exists on every target node
- every configured VM ID is unused or intentionally managed by this workspace
- the controller can reach TCP `8006`
- the provider's SSH block can reach each Proxmox host as `root`
- time synchronization is healthy

Useful checks on a Proxmox member:

```bash
pvecm status
pvesm status
ip link show
timedatectl
```

### Automation identity

Use a dedicated API user and token, for example:

```text
terraform-user@pve!homelab
```

An initial build may use a broad built-in role while the workflow is being
proven. A production-quality deployment should create and test a
least-privilege role. When token privilege separation is enabled, both the user
and token ACLs must permit the provider's operations.

### TLS

`proxmox_insecure = true` accepts the Proxmox API certificate without normal
verification. This is a bootstrap convenience, not the target security state.
Install a trusted certificate and change the variable to `false` when practical.

## Network and DNS

Every Fedora VM needs:

- its configured static address
- a reachable default gateway
- working DNS resolution
- outbound HTTPS for Fedora packages, container images, GitHub, Helm
  repositories, Azure, and ACME
- TCP `22` from the Ansible controller
- unrestricted required Kubernetes and Cilium traffic between cluster nodes

Terraform supplies DNS through cloud-init. The current implementation declares
the DNS server list in `terraform/main.tf`, so replace those reference values
before applying:

```text
<GATEWAY_OR_INTERNAL_DNS_IP>
<SECONDARY_DNS_IP>
```

After Terraform creates a VM, verify from the VM:

```bash
ip address
ip route
resolvectl status
getent hosts registry.k8s.io
curl -fsSI https://registry.k8s.io
```

If any subnet changes, update all of these together:

- Terraform node addresses, gateway, and DNS
- Ansible inventory and management CIDRs
- kubeadm control-plane endpoint
- kubelet CSR approver IP prefixes
- MetalLB pool
- Traefik VIP
- router forwarding
- split DNS or internal DNS overrides

## Router and Public DNS

Router rules for this design:

```text
WAN TCP 80  -> <CONTROL_PLANE_IP> TCP <TRAEFIK_HTTP_NODEPORT>
WAN TCP 443 -> <CONTROL_PLANE_IP> TCP <TRAEFIK_HTTPS_NODEPORT>
```

Create Cloudflare DNS records for each public hostname. For the current direct
port-forward design, the record resolves to the home public address.

Before relying on inbound hosting, confirm:

- the ISP does not block inbound TCP 80/443
- the connection is not behind carrier-grade NAT
- dynamic public IP changes are handled
- Cloudflare proxy mode matches the intended origin design
- NAT reflection or split DNS supports testing from inside the LAN

The wildcard certificate does not create DNS records.

## Controller Workstation

Required tools:

- Git
- OpenSSH client with FIDO2 support when using a YubiKey
- Terraform
- Python 3
- Ansible Core 2.16 or newer
- `ansible-lint`
- `yamllint`
- `kubectl`
- SOPS and age
- Flux CLI for operator convenience
- `jq`
- a DNS client such as `dig`

Check:

```bash
git --version
ssh -V
terraform version
python3 --version
ansible --version
ansible-lint --version
yamllint --version
kubectl version --client
sops --version
age --version
flux version --client
jq --version
```

The Ansible controller needs a private SSH identity matching a public key
injected by Terraform. See
[Controller authentication](CONTROLLER-AUTHENTICATION.md).

## HCP Terraform

The HCP organization and workspace are declared in `terraform/main.tf`.
Replace both placeholders with an existing CLI-driven workspace:

```text
Organization: <HCP_ORGANIZATION>
Workspace:    <HCP_WORKSPACE>
```

Authenticate and initialize:

```bash
cd terraform
terraform login
terraform init
```

Confirm the correct workspace before any destructive operation:

```bash
terraform state list
terraform show
```

## GitHub and Flux

Flux follows:

```text
Owner:      <GITHUB_OWNER>
Repository: <REPOSITORY>
Branch:     <GIT_BRANCH>
Path:       <FLUX_CLUSTER_PATH>
```

Set those values, plus the Flux commit-author name and email, in
`ansible/roles/flux_bootstrap/defaults/main.yml`.

For a completely new cluster, create a short-lived fine-grained personal
access token scoped only to this repository:

```text
Administration: Read and write
Contents:       Read and write
Metadata:       Read-only
```

Administration access is required because Flux creates an SSH deploy key.
After bootstrap, Flux reads the repository with the generated read-only deploy
key and the personal token is no longer required.

## SOPS Recovery Identity

Required default path:

```text
~/.config/sops/age/keys.txt
```

Validate without printing it:

```bash
SOPS_KEY_PATH="${SOPS_AGE_KEY_FILE:-$HOME/.config/sops/age/keys.txt}"
test -s "$SOPS_KEY_PATH"
grep -q '^AGE-SECRET-KEY-' "$SOPS_KEY_PATH"

sops --decrypt \
  kubernetes/infrastructure/configs/external-secrets/azure-credentials.sops.yaml \
  >/dev/null
```

Keep at least two tested offline copies. The Kubernetes Secret is not a backup
of the recovery identity.

## Azure Key Vault

The External Secrets configuration expects:

```text
Vault URL:
https://<KEY_VAULT_NAME>.vault.azure.net/

Required secret names:
cloudflare-api-token
grafana-admin-user
grafana-admin-password
letsencrypt-production-account-key
linkding-superuser-name
linkding-superuser-password
tailscale-operator-client-id
tailscale-operator-client-secret
```

The SOPS-encrypted `azure-keyvault-bootstrap` Secret contains the service
principal identity used by External Secrets Operator. That identity needs only
the permissions required to read the referenced secrets.

Verify names and enabled state without returning values:

```bash
az keyvault secret list \
  --vault-name "<KEY_VAULT_NAME>" \
  --query '[].{name:name,enabled:attributes.enabled}' \
  --output table
```

Do not use a command that prints secret values in terminal output or
documentation.

## Cloudflare

The Key Vault entry `cloudflare-api-token` must contain a token capable of
editing DNS records for the certificate zone. Scope it to the required zone and
the minimum DNS permission.

Public records for applications are managed separately from ACME. Create only
the records required by the public workloads, for example:

```text
<PUBLIC_DOMAIN>
www.<PUBLIC_DOMAIN>
preview.<PUBLIC_DOMAIN>
```

Grafana can retain a public route during migration, but Homepage and Linkding
use Tailscale and do not need public records.

## Tailscale

Before Flux installs the operator:

1. Enable MagicDNS and HTTPS certificates for the tailnet.
2. Define `tag:k8s-operator` and `tag:k8s` in the tailnet policy.
3. Create a dedicated OAuth client for the operator with only the required
   Services, Devices, and Auth Keys write permissions, scoped to
   `tag:k8s-operator`.
4. Store its client ID and secret in Azure Key Vault using the names above.
5. Replace the tailnet domain in the Homepage Deployment and customize the
   private service links.

The OAuth secret is shown only once when created. Store it before leaving the
credential page and never commit it.

## Final Preflight Checklist

Run this checklist immediately before a new deployment:

- [ ] Proxmox has quorum and all target nodes are online.
- [ ] Target datastores, bridges, and VM IDs are correct.
- [ ] Node and MetalLB addresses are reserved.
- [ ] Controller tools are installed.
- [ ] HCP Terraform login and workspace are correct.
- [ ] `terraform/terraform.tfvars` exists and is ignored.
- [ ] The SSH private identity and matching public key are available.
- [ ] The SOPS identity exists, is backed up, and decrypts the manifest.
- [ ] Azure Key Vault contains all eight required values.
- [ ] A short-lived GitHub token can be created.
- [ ] Cloudflare DNS and API access are available.
- [ ] Tailscale MagicDNS, HTTPS certificates, tags, and OAuth client are ready.
- [ ] Router rules are documented.
- [ ] Any important application data has an external backup.

Continue with [Configuration and secrets](CONFIGURATION-AND-SECRETS.md).
