# Environment Setup and External Prerequisites

This guide lists the infrastructure and controller requirements that must exist before the repository can deploy the Kubernetes platform.

It is not a complete Proxmox, network, Tailscale, GitHub, Azure, or HCP Terraform installation guide.

## Reference Topology

```text
pve1 -> k8s-worker-01  192.168.0.50
pve2 -> k8s-worker-02  192.168.0.51
pve3 -> k8s-master-01  192.168.0.52
```

Shared network values:

```text
Default gateway       192.168.0.1
Traefik MetalLB VIP   192.168.0.220
Traefik HTTP NodePort 32492
Traefik HTTPS NodePort 30860
```

## Proxmox Requirements

Before running Terraform, verify:

```bash
pvecm status
```

The Proxmox cluster must have quorum. Also confirm:

- All three Proxmox nodes are online.
- The image/import datastore exists on every node that downloads the Fedora image.
- The VM disk datastore exists on every target node.
- The configured Linux bridge exists on every target node.
- The selected VM IDs are unused.
- The Proxmox API is reachable from the Terraform controller.
- Time synchronization is working on all Proxmox nodes.

## Proxmox API Identity

Use a dedicated automation identity instead of `root@pam` credentials.

A typical token ID is:

```text
terraform-user@pve!homelab
```

For initial lab deployment, a dedicated user or token with the built-in `PVEAdmin` role at `/` is simple and testable. It is broader than least privilege. Once the full plan, apply, and destroy workflow is stable, replace it with a custom role containing only the required privileges.

When token privilege separation is enabled, verify that the token itself has the ACL required by the provider.

## Proxmox TLS

The current example uses:

```hcl
proxmox_insecure = true
```

This accepts the Proxmox certificate without normal trust validation. A stronger setup installs a trusted certificate and sets the value to `false`.

## Network Requirements

The Kubernetes VMs require:

- Static IPv4 addresses.
- A reachable default gateway.
- Working DNS resolution.
- Internet access for Fedora packages, container images, Helm repositories, GitHub, and certificate issuance.
- TCP 22 from the Ansible controller.
- Kubernetes control-plane and kubelet traffic between nodes.
- Cilium traffic between nodes.
- Access from the router to the selected Traefik NodePort target node.

If the subnet changes, update all of the following:

- Terraform node addresses and gateway.
- Ansible inventory.
- Ansible group variables and firewall source networks.
- MetalLB address pool.
- Router port forwards.
- Internal DNS overrides, if used.

## Router Port Forwards

The current router forwards to the control-plane node because the router does not accept the MetalLB virtual IP as a forwarding target.

```text
WAN TCP 80  -> 192.168.0.52 TCP 32492
WAN TCP 443 -> 192.168.0.52 TCP 30860
```

Traefik uses `externalTrafficPolicy: Cluster`, allowing traffic received by the master node's NodePort to be forwarded to a Traefik Pod on another Kubernetes node.

The NodePorts must remain pinned in the Traefik HelmRelease. Do not rely on automatically allocated NodePorts during a rebuild.

## DNS Requirements

Public records such as `grafana.mccruden.com` must resolve to the router's public address unless Cloudflare proxying or another ingress design is intentionally used.

A wildcard certificate does not create DNS records. DNS, router forwarding, Traefik routing, and certificate issuance are separate parts of the request path.

See [Ingress, DNS, and TLS](INGRESS-DNS-AND-TLS.md).

## Controller Workstation

Required tools:

- Git
- OpenSSH client
- Terraform
- Python 3
- Ansible Core
- `ansible-lint`
- `yamllint`
- `kubectl`
- Flux CLI for local convenience, or SSH access to the control-plane copy installed by Ansible
- A private SSH key matching the public key injected by Terraform
- The SOPS age private key used for encrypted repository files

Useful checks:

```bash
git --version
ssh -V
terraform version
python3 --version
ansible --version
ansible-lint --version
yamllint --version
kubectl version --client
```

## SSH Authentication Options

### YubiKey-backed SSH

The repository includes `scripts/ansible-yubikey`. It forces Ansible to use a FIDO2 SSH key directly and disables the SSH agent for that run.

Default key path:

```text
~/.ssh/id_ed25519_sk
```

Override it with:

```bash
export ANSIBLE_YUBIKEY_PATH="$HOME/.ssh/another-security-key"
```

Run playbooks from the repository with:

```bash
../scripts/ansible-yubikey playbooks/system-init.yml
```

A PIN prompt or physical touch may be required depending on the SSH key configuration.

### Standard file-based SSH key

A user without a YubiKey can use a normal OpenSSH private key such as:

```text
~/.ssh/id_ed25519
```

Reference that key in Ansible inventory or group variables and run:

```bash
ansible-playbook playbooks/system-init.yml
```

Protect the private key:

```bash
chmod 600 ~/.ssh/id_ed25519
```

The YubiKey wrapper changes only the SSH connection used by Ansible. It does not change the GitHub token or SOPS workflow.

See [Controller authentication](CONTROLLER-AUTHENTICATION.md).

## HCP Terraform

The Terraform configuration contains an HCP Terraform `cloud` block. Configure the correct organization and workspace, then authenticate:

```bash
terraform login
```

Use a CLI-driven workspace when plans and applies are initiated locally.

## GitHub and Flux

The first Flux bootstrap of a replacement cluster uses a GitHub fine-grained personal access token.

The current Ansible role runs Flux with SSH deploy-key authentication:

```text
--token-auth=false
--read-write-key=false
```

Create the token with access limited to the homelab repository and these repository permissions:

```text
Administration: Read and write
Contents:       Read and write
Metadata:       Read-only
```

Administration must be read/write because Flux creates the repository deploy key when `--token-auth=false` is used.

Use a short expiration. The token is needed only during a new bootstrap. Flux uses the generated read-only SSH deploy key afterward.

## SOPS Age Key

The Ansible controller must have the age private key used by `.sops.yaml`.

Default path:

```text
~/.config/sops/age/keys.txt
```

Optional override:

```bash
export SOPS_AGE_KEY_FILE="/secure/path/keys.txt"
```

Validate the file without printing the private key:

```bash
test -s "${SOPS_AGE_KEY_FILE:-$HOME/.config/sops/age/keys.txt}" \
  && echo "SOPS age key file found"

grep -q '^AGE-SECRET-KEY-' \
  "${SOPS_AGE_KEY_FILE:-$HOME/.config/sops/age/keys.txt}" \
  && echo "SOPS age identity found"
```

The key must be backed up outside both Git and the Kubernetes cluster.

## Azure Key Vault and External Secrets

The current platform expects:

- An Azure Key Vault containing the application and platform secrets referenced by ExternalSecret resources.
- Azure credentials encrypted with SOPS in the repository.
- A working ClusterSecretStore after decryption.
- A Cloudflare API token in Azure Key Vault for cert-manager DNS-01 operations.
- Grafana administrative credentials in Azure Key Vault.

The exact secret names must match the ExternalSecret manifests under `kubernetes/infrastructure/configs/external-secrets/`.

## Remote Access

The reference environment uses Tailscale for remote access. Local LAN access is sufficient for deployment. This repository does not install or manage Tailscale.

## Official References

- [Flux bootstrap for GitHub](https://fluxcd.io/flux/installation/bootstrap/github/)
- [GitHub personal access token management](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/managing-your-personal-access-tokens)
