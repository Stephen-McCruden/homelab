# Website and Applications

This document describes the applications currently deployed and the standards
for adding another workload to this three-node cluster.

## Current Application Set

| Application | Exposure | State |
|---|---|---|
| Production website | Public Traefik ingress | Stateless, two replicas |
| Website preview | Public Traefik ingress | Stateless, two replicas, no-index middleware |
| Homepage | Tailscale-only | Stateless, Git-managed configuration |
| Linkding | Tailscale-only | One replica, 5 GiB Longhorn PVC |
| Mealie | Tailscale-only | One replica, 10 GiB Longhorn PVC |
| FreshRSS | Tailscale-only | One replica, 5 GiB Longhorn PVC |
| Grafana | Tailscale plus retained Traefik route | Monitoring UI; 5 GiB Longhorn PVC |

## Website Decision

Use **Astro with Markdown/MDX content**, built into a static container and
served from Kubernetes on the home hardware.

Why:

- posts are versioned in Git
- the published site needs no database or PVC
- a static build has a small runtime and attack surface
- two replicas can run on separate nodes
- images can be optimized during the build
- the same repository can contain portfolio pages, project write-ups,
  postmortems, and the blog

Ghost remains a strong choice when the admin editor is the primary requirement,
but it introduces a database, uploads, PVCs, application backups, and a restore
sequence. That is unnecessary for a Git-native technical portfolio.

## Content and Images

The website source and content belong in a separate repository:

```text
portfolio-website/
├── src/
│   ├── content/
│   │   └── blog/
│   │       └── rebuilding-kubernetes.mdx
│   └── assets/
│       └── blog/
│           └── rebuilding-kubernetes/
│               ├── topology.webp
│               └── grafana-dashboard.webp
├── public/
├── Dockerfile
└── .github/workflows/
```

Use `src/assets` for images imported by posts so Astro can optimize dimensions,
formats, and responsive output at build time. Use `public/` only for assets that
must retain an exact filename or are not processed.

Example frontmatter:

```yaml
---
title: "Rebuilding My Kubernetes Homelab"
description: "What failed, how I diagnosed it, and what made the rebuild repeatable."
publishedAt: 2026-08-01
updatedAt: 2026-08-01
tags:
  - kubernetes
  - ansible
  - incident-review
draft: false
---
```

## Editing Experience

Start with one of these:

1. Edit Markdown/MDX in Neovim or Obsidian, preview locally, and push.
2. Add Keystatic in local mode for a structured admin-like editor that writes
   files into the checkout.
3. Later enable Keystatic GitHub mode if browser-based editing is worth the
   GitHub authentication and application-secret work.

Keep the public runtime static even if an editor UI is added. Do not expose an
unauthenticated `/keystatic` route.

## Build and Deployment Flow

```text
write Markdown/MDX and add images
  -> pull request
  -> lint, type-check, and build
  -> build immutable container image
  -> push image to GHCR
  -> Flux selects the channel-specific immutable image
  -> image automation commits the selected reference to Git
  -> Flux deploys two replicas
  -> Traefik serves the configured public hostname
```

Deployment requirements:

- multi-stage Docker build
- unprivileged runtime container
- read-only root filesystem when supported
- two replicas with anti-affinity
- readiness and liveness probes
- resource requests and limits
- immutable image tag or digest
- HTTPS Ingress through Traefik
- Blackbox Exporter probe
- no PVC

Because the site is on the home cluster, it will be unavailable during total
cluster rebuilds, extended power loss, WAN failure, or control-plane loss. That
is an honest consequence of the self-hosting requirement. A future independent
static mirror can improve availability without changing the primary hosting
location.

## Private Daily-Use Applications

Homepage is the private entry point. Linkding, Mealie, and FreshRSS provide
bookmarking, household meal planning, and RSS reading behind Tailscale.

### Homepage

Purpose:

- one private landing page for Grafana, Linkding, Proxmox, Longhorn, and other
  services
- health indicators and selected service widgets
- Git-managed YAML configuration

Current deployment:

- stateless
- Tailscale only
- configuration in Git, not edited in the Pod
- ConfigMap projected as a directory so updates are not pinned by `subPath`
- read-only discovery RBAC for the displayed Kubernetes resources
- no broad cluster-admin ServiceAccount

Before using the repository elsewhere, replace the dashboard title, tailnet
domain, Proxmox links, public-site links, and repository bookmark in the
Homepage ConfigMap and Deployment.

Homepage is not a monitoring system. Grafana, Prometheus, and alerts remain the
source of operational truth.

### Linkding

Purpose:

- searchable personal bookmarks
- tags, notes, and browser extensions
- optional archived-page variant

Current deployment:

- private Tailscale hostname
- one replica
- 5 GiB Longhorn PVC
- SQLite initially
- credentials restored through External Secrets
- `Recreate` update strategy so only one Pod writes the `ReadWriteOnce` volume

An off-cluster backup and restore test are still required before the data is
treated as recoverable.

### Mealie

Mealie stores recipes, meal plans, shopping lists, images, and its SQLite
database on a 10 GiB Longhorn claim. It runs as UID/GID 911 under the restricted
Pod Security Standard with a read-only root filesystem. Public registration is
disabled, and the only ingress uses Tailscale.

On a new volume, sign in with the upstream first-run account and immediately
change its email and password:

```text
Username: changeme@example.com
Password: MyPassword
```

Use Mealie's supported backup export and copy it off-cluster before treating
the recipe library as recoverable.

### FreshRSS

FreshRSS stores configuration, subscriptions, users, and SQLite data on a 5 GiB
Longhorn claim. An init container creates the administrator from Azure Key
Vault, and the built-in cron refreshes feeds twice each hour. The Google
Reader-compatible API is enabled for mobile clients.

The official FreshRSS image initializes Apache, permissions, and cron as root.
Its namespace therefore enforces the `baseline` Pod Security Standard while
auditing and warning against `restricted`; the Pod drops all capabilities
except the small set required for ownership and Apache worker identity changes.
It has no Kubernetes API token and is reachable only through Tailscale.

## Optional Future Workloads

No additional application is required to complete the current platform. If the
scope grows later, choose workloads that justify their storage, backup, access,
and operational cost.

| Application | Value | Data risk | Notes |
|---|---|---|---|
| Gatus or Uptime Kuma | Friendly service status | Low/medium | Complements, rather than replaces, Prometheus |
| ntfy | Alert delivery | Medium | Keep registration and administration private |
| NetBox | Network source of truth | Medium/high | More useful as VLAN, rack, circuit, and IPAM data grows |

## Applications to Delay

### Immich

Photo storage is resource- and data-intensive. Delay it until storage capacity,
GPU strategy, off-site backup, and full restore are proven.

### Vaultwarden

A password manager creates a high-impact security boundary. Deploy one only
when its independent backup, authentication, and recovery controls are
stronger than the system it would replace.

### Self-hosted Git forge or registry

GitHub and GHCR already satisfy the source and image workflow. Forgejo or Harbor
can be valuable later for independence, but they are not the best use of
current cluster capacity.

### Public administrative dashboards

Do not publicly expose Homepage, Linkding, Mealie, FreshRSS, Longhorn UI,
Proxmox, or internal observability merely because Traefik and a wildcard
certificate make it easy.

## Standard Application Definition of Done

Every new application must have:

- a clear owner and source repository
- a version-pinned image or Helm chart
- namespace and least-privilege RBAC
- resource requests and limits
- readiness and liveness probes
- public, LAN-only, or Tailscale-only exposure decision
- ExternalSecret references instead of plaintext values
- PVC and external backup design when stateful
- restore procedure and test when important
- metrics/log collection
- user-visible acceptance test
- inclusion in the full rebuild and health documentation

## Recommended Order From Here

1. Customize Homepage for the target environment.
2. Verify observability data after Pod deletion and rescheduling.
3. Configure an off-cluster Longhorn backup target and prove Linkding restore.
4. Add host journals and private appliance syslog to Alloy.
5. Prove a clean rebuild and record measured recovery results.
6. Add alert delivery and update automation.
7. Add backup and restore procedures for Mealie and FreshRSS before relying on
   their state.

## References

- [Astro content collections](https://docs.astro.build/en/guides/content-collections/)
- [Astro images](https://docs.astro.build/en/guides/images/)
- [Astro Docker builds](https://docs.astro.build/en/recipes/docker/)
- [Keystatic with Astro](https://keystatic.com/docs/installation-astro)
- [Keystatic GitHub mode](https://keystatic.com/docs/github-mode)
- [Homepage](https://gethomepage.dev/)
- [Homepage Kubernetes installation](https://gethomepage.dev/installation/k8s/)
- [Linkding installation](https://linkding.link/installation/)
- [Mealie installation](https://docs.mealie.io/documentation/getting-started/installation/installation-checklist/)
- [FreshRSS Docker deployment](https://github.com/FreshRSS/FreshRSS/blob/edge/Docker/README.md)
- [Paperless-ngx setup](https://docs.paperless-ngx.com/setup/)
