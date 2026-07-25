# Storage and Backups

This document records the target storage design. Longhorn is not installed yet,
and current monitoring/application data is intentionally ephemeral.

## Non-Negotiable Distinction

Longhorn replicas provide availability across nodes. They do not provide an
independent backup against:

- accidental deletion
- bad application migrations
- corrupted replicated data
- malicious changes
- loss of the entire Proxmox cluster
- loss of the building

No stateful application is complete until its restore has been tested from a
backup target outside the Kubernetes cluster.

## Target Disk Layout

Each Kubernetes VM should have:

```text
scsi0  Fedora root disk
scsi1  dedicated Longhorn data disk
```

Target mount:

```text
/var/lib/longhorn
```

Recommended initial sizing for this hardware:

| Disk | Size | Purpose |
|---|---:|---|
| Root | 40-60 GiB | Fedora, images, logs, and ephemeral data |
| Longhorn | 150-200 GiB | Kubernetes persistent volumes |

Use the Longhorn V1 data engine with ext4 or XFS. Its host prerequisites include
the iSCSI initiator and NFS client support for applicable backup/RWX workflows.
The V2 engine adds complexity and resource requirements that are not justified
for the current 4-vCPU nodes.

## Ownership

| Concern | Owner |
|---|---|
| Add second virtual disk | Terraform |
| Partition, format, mount, and install prerequisites | Ansible |
| Install Longhorn and StorageClasses | Flux |
| Request PVCs | Application manifests |
| Snapshot and backup schedules | Flux/Longhorn configuration |
| External backup target | External infrastructure |
| Restore validation | Operator runbook |

Do not format a disk by guessed device name. Ansible must identify the intended
disk deterministically and fail if the device state is ambiguous.

## Implementation Order

### Phase 1: Infrastructure

1. Resolve the current root-disk default/example inconsistency.
2. Add a dedicated disk to every VM in Terraform.
3. Prove Terraform does not replace or reformat an existing data disk
   unexpectedly.
4. Add Ansible packages and persistent mount configuration.
5. Validate the mount exists on all nodes before Flux can install Longhorn.

### Phase 2: Longhorn

1. Add a separate Flux `infrastructure-storage` Kustomization.
2. Install the Longhorn chart and CRDs.
3. Configure only the dedicated mount as schedulable.
4. Use a two-replica default for space efficiency on three small nodes.
5. Keep the StorageClass non-default during testing.
6. Restrict the UI to LAN/Tailscale access.

Suggested dependency placement:

```text
flux-system
├─ infrastructure-storage
├─ infrastructure-controllers
│  └─ infrastructure-configs
│     └─ applications
└─ kubelet CSR approver
   └─ Metrics Server
```

Controllers that need PVCs can later depend on storage explicitly.

### Phase 3: Failure Tests

Test:

- dynamic PVC provisioning
- attach, mount, write, detach, and reattach
- Pod rescheduling to another node
- loss and return of one worker
- Longhorn replica rebuild
- disk-full guardrails
- volume snapshot
- external backup
- restore to a new volume
- restore after deleting the original namespace

Record time to recover and any manual step.

### Phase 4: Migrate Existing Data

Initial allocations:

| Workload | Starting size |
|---|---:|
| Prometheus | 20-30 GiB |
| Alertmanager | 2-5 GiB |
| Grafana | 5-10 GiB |
| Loki | 30-50 GiB, governed by retention |
| Linkding | 2-5 GiB |

Size from measured usage, not only maximum available capacity.

## Backup Target

Preferred options:

1. S3-compatible object storage outside the Kubernetes cluster
2. Azure Blob Storage
3. NFS storage on separate hardware with its own backup

A MinIO instance using the same Longhorn cluster is not an independent backup.

Store backup credentials in Azure Key Vault and synchronize them with External
Secrets. Do not commit them in a Longhorn values file.

## Application-Level Backups

Volume backups alone may not be application-consistent. For databases:

- create a native logical dump
- write it to a controlled backup staging volume
- copy it off-cluster
- retain the matching application version and restore procedure
- test the restore into an isolated namespace

For SQLite applications such as Linkding, either stop writes for a consistent
copy or use the application's supported backup/export mechanism.

## Recovery Objectives

Define per workload:

| Class | Example | Initial RPO | Initial RTO |
|---|---|---:|---:|
| Rebuildable | Homepage, static website | Git commit | 30-60 minutes |
| Operational | Grafana config, Linkding | 24 hours | 2-4 hours |
| Important personal data | Paperless, photos | 1-6 hours | 4-12 hours |

These are proposed targets. Replace them with measured restore results.

## Destruction Gate

Before `terraform destroy`, require:

- a recent successful external backup
- a successful restore test for important data
- documented backup target credentials
- the current Git revision
- confirmation that the intended HCP workspace is selected

If these cannot be demonstrated, postpone destruction.

## References

- [Longhorn installation requirements](https://longhorn.io/docs/latest/deploy/install/)
- [Longhorn best practices](https://longhorn.io/docs/latest/best-practices/)
- [Longhorn multiple disk support](https://longhorn.io/docs/latest/nodes-and-volumes/nodes/multidisk/)
- [Longhorn backup and restore](https://longhorn.io/docs/latest/)
