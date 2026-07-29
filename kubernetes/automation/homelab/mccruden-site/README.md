# Website Image Automation

This directory is intentionally limited to the public website release
pipeline. It scans the configured GHCR image repository, selects the latest
immutable preview and production tags, and commits only the marked image
references under the two website application directories.

The directory names are repository implementation details. A fork should
replace the image repository, Git owner, hostnames, and site-specific labels
before enabling automation.

Preview accepts only `preview-<GitHub run ID>-<commit SHA>` tags. Production
accepts only `production-<GitHub run ID>-<commit SHA>` tags after the one-time
bootstrap image. Tags from one channel cannot be selected by the other.

The `flux-system` GitHub deploy key must have write access. New cluster
bootstraps request a writable key through the `flux_bootstrap` Ansible role.
