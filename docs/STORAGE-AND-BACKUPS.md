# Storage and Backups

Longhorn is installed and provides the cluster's default persistent
StorageClass. This document records the current design, its limits, and the work
still required before full-cluster destruction is safe.

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

## Current Implementation

| Item | Current state |
|---|---|
| Host prerequisites | Managed by Ansible on every Kubernetes node |
| Data path | `/var/lib/longhorn` on each VM root filesystem |
| Data engine | Longhorn V1 |
| Filesystem | ext4 |
| Default replica count | 2 |
| Reclaim policy | `Retain` |
| Data locality | Best effort |
| Storage reserve | 30% of each default disk |
| Minimum free space | 25% |
| Current PVC consumers | Linkding 5 GiB, Mealie 10 GiB, FreshRSS 5 GiB; all `ReadWriteOnce` |
| Off-cluster backup target | Not configured |
| Restore proof | Not completed |

Ansible installs `iscsi-initiator-utils`, `nfs-utils`, `cryptsetup`, and
device-mapper support; loads `iscsi_tcp`; and enables `iscsid`. Flux installs
Longhorn and makes its StorageClass the default.

Quick validation:

```bash
kubectl get storageclass
kubectl get helmrelease longhorn --namespace longhorn-system
kubectl get nodes.longhorn.io,volumes.longhorn.io \
  --namespace longhorn-system
kubectl get persistentvolumeclaim --all-namespaces
```

## Disk Layout

The current implementation uses one virtual root disk per VM:

```text
scsi0  Fedora, container images, logs, and Longhorn data
```

This is simple and works for the present lab, but it couples operating-system
and persistent-volume capacity. A later storage change may add a dedicated
virtual disk mounted at `/var/lib/longhorn`. That change must include
deterministic disk identification, migration, rollback, and restore testing; do
not format a device selected only by a guessed Linux name.

Review `vm_disk_size` before deployment. The Terraform variable default and
the example file currently use different sizes, and Longhorn shares that root
disk.

## Ownership

| Concern | Owner |
|---|---|
| VM root disk | Terraform |
| Install iSCSI/NFS prerequisites and kernel modules | Ansible |
| Install Longhorn and StorageClasses | Flux |
| Request PVCs | Application manifests |
| Snapshot and backup schedules | Flux/Longhorn configuration |
| External backup target | External infrastructure |
| Restore validation | Operator runbook |

Do not format a disk by guessed device name. Ansible must identify the intended
disk deterministically and fail if the device state is ambiguous.

## Remaining Validation

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

## Planned Consumers

Initial allocations:

| Workload | Starting size |
|---|---:|
| Prometheus | 20-30 GiB |
| Alertmanager | 2-5 GiB |
| Grafana | 5-10 GiB |
| Loki | 30-50 GiB, governed by retention |
| Linkding | 2-5 GiB |
| Mealie | 10 GiB initially |
| FreshRSS | 5 GiB initially |

Linkding, Mealie, and FreshRSS already request persistent storage. Prometheus,
Alertmanager, and Grafana remain ephemeral until their Helm values are
migrated. Size every claim from measured usage and retention requirements, not
only available capacity.

## Backup Target

Preferred options:

1. S3-compatible object storage outside the Kubernetes cluster
2. Azure Blob Storage
3. NFS storage on separate hardware with its own backup

A MinIO instance using the same Longhorn cluster is not an independent backup.

Store backup credentials in Azure Key Vault and synchronize them with External
Secrets. Do not commit them in a Longhorn values file. Until an external target
and restore proof exist, a Terraform destroy or total Proxmox loss will destroy
the only copies of Longhorn data.

## Application-Level Backups

Volume backups alone may not be application-consistent. For databases:

- create a native logical dump
- write it to a controlled backup staging volume
- copy it off-cluster
- retain the matching application version and restore procedure
- test the restore into an isolated namespace

For SQLite applications such as Linkding, Mealie, and FreshRSS, either stop
writes for a consistent copy or use the application's supported backup/export
mechanism.

## Recovery Objectives

Define per workload:

| Class | Example | Initial RPO | Initial RTO |
|---|---|---:|---:|
| Rebuildable | Homepage, static website | Git commit | 30-60 minutes |
| Operational | Grafana config, Linkding, Mealie, FreshRSS | 24 hours | 2-4 hours |
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
