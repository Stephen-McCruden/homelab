# Website and Applications

This document is the application roadmap. It favors workloads that are useful,
demonstrate sound platform engineering, and fit the current three-node cluster.

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

Recommended separate repository:

```text
mccruden-website/
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
  -> update the pinned image digest/tag in GitOps
  -> Flux deploys two replicas
  -> Traefik serves mccruden.com and www.mccruden.com
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

## Homepage and Linkding

The dashboard application is named **Homepage**. The bookmark application is
**Linkding**.

### Homepage

Purpose:

- one private landing page for Grafana, Linkding, Proxmox, Longhorn, and other
  services
- health indicators and selected service widgets
- Git-managed YAML configuration

Deployment:

- stateless
- LAN/Tailscale only
- configuration in Git, not edited in the Pod
- minimum RBAC if Kubernetes discovery is enabled
- no broad cluster-admin ServiceAccount

Homepage is not a monitoring system. Grafana, Prometheus, and alerts remain the
source of operational truth.

### Linkding

Purpose:

- searchable personal bookmarks
- tags, notes, and browser extensions
- optional archived-page variant

Deployment:

- private hostname through LAN/Tailscale
- one replica
- Longhorn PVC
- SQLite initially
- scheduled export/database backup to the external target
- restore test before relying on it

Do not deploy Linkding before storage and backup are proven.

## Recommended Application Queue

| Order | Application | Value | Data risk | Notes |
|---:|---|---|---|---|
| 1 | Public Astro website | Portfolio and blog | Low | Stateless; deploy after rebuild proof |
| 2 | Homepage | Daily service dashboard | Low | Private and stateless |
| 3 | Linkding | Bookmark knowledge base | Medium | Needs Longhorn and backup |
| 4 | Gatus or Uptime Kuma | Friendly service status | Low/medium | Blackbox Exporter remains primary SLI source |
| 5 | Mealie | Household recipes and meal planning | Medium | Useful for a pescatarian household; SQLite is adequate initially |
| 6 | ntfy | Alert delivery | Medium | Keep registration and administration private |
| 7 | FreshRSS or Miniflux | Technical news/RSS | Medium | Small footprint; requires backed-up state |
| 8 | Paperless-ngx | Searchable personal documents | High | Add only after strong auth, backups, and restore tests |
| 9 | Actual Budget | Private budgeting | High | Useful, but financial data raises the security bar |
| 10 | NetBox | Network source of truth | Medium/high | Valuable when VLANs, racks, circuits, and IPAM grow |

## Applications to Delay

### Immich

Photo storage is resource- and data-intensive. Delay it until storage capacity,
GPU strategy, off-site backup, and full restore are proven.

### Vaultwarden

The operator already uses `pass`, GPG, and YubiKey-backed keys. Adding a second
password system creates a new high-impact security boundary without a current
need.

### Self-hosted Git forge or registry

GitHub and GHCR already satisfy the source and image workflow. Forgejo or Harbor
can be valuable later for independence, but they are not the best use of
current cluster capacity.

### Public administrative dashboards

Do not publicly expose Homepage, Linkding administration, Longhorn UI, Proxmox,
or internal observability merely because Traefik and a wildcard certificate
make it easy.

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

1. Prove one clean rebuild.
2. Deploy the stateless Astro website and Homepage.
3. Add Longhorn prerequisites, Longhorn, and external backups.
4. Persist the monitoring stack.
5. Add Loki and Alloy.
6. Deploy Linkding.
7. Add Mealie and alert delivery.
8. Add high-sensitivity applications only after access and restore controls are
   mature.

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
- [Paperless-ngx setup](https://docs.paperless-ngx.com/setup/)
