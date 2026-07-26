# mccruden.com image automation

This directory is intentionally limited to the mccruden.com release pipeline.
It scans the public GHCR image repository, selects the latest immutable preview
and production tags, and commits only the marked image references under:

- `kubernetes/applications/homelab/mccruden-site`
- `kubernetes/applications/homelab/mccruden-site-production`

Preview accepts only `preview-<GitHub run ID>-<commit SHA>` tags. Production
accepts only `production-<GitHub run ID>-<commit SHA>` tags after the one-time
bootstrap image. Tags from one channel cannot be selected by the other.

The `flux-system` GitHub deploy key must have write access. New cluster
bootstraps request a writable key through the `flux_bootstrap` Ansible role.
