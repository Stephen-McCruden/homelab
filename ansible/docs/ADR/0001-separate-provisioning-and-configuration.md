# FILE PATH: docs/ADR/0001-separate-provisioning-and-configuration.md
# ADR 0001: Separate provisioning from guest configuration

## Status
Accepted

## Decision
Terraform provisions and destroys VMs. Ansible configures their operating systems. SSH host-key reconciliation bridges ephemeral VM replacement without disabling host-key checking globally.

## Consequences
Each tool has a clear ownership boundary, rebuilds are predictable, and configuration remains independently testable.
