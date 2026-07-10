> **FILE PATH:** `FILE-MAP.md`  
> Keep this file at the root of the Ansible project.

# Exact File Placement Map

Every generated file now includes its own exact destination path at the very top.

```text
ansible-k8s-single-playbook-v3/
├── ansible.cfg
├── README.md
├── FILE-MAP.md
├── playbooks/
│   └── system-init.yml
├── inventory/
│   └── hosts.yml
├── procedures/
│   └── SYSTEM-INIT-PROCEDURE.md
├── scripts/
│   └── reconcile-known-host.sh
└── roles/
    ├── prereqs/
    │   ├── defaults/
    │   │   └── main.yml
    │   ├── handlers/
    │   │   └── main.yml
    │   ├── tasks/
    │   │   ├── main.yml
    │   │   └── verify.yml
    │   └── templates/
    │       ├── kubernetes.repo.j2
    │       ├── kubernetes-modules.conf.j2
    │       └── kubernetes-sysctl.conf.j2
    └── hardening/
        ├── defaults/
        │   └── main.yml
        ├── handlers/
        │   └── main.yml
        ├── tasks/
        │   ├── main.yml
        │   └── verify.yml
        └── templates/
            └── 20-ansible-hardening.conf.j2
```

## The three `main.yml` files in each role

They have the same filename because Ansible uses the parent directory to determine their function.

### Prerequisites role

| Exact path | Function |
|---|---|
| `roles/prereqs/defaults/main.yml` | Default variables for the prerequisites role |
| `roles/prereqs/tasks/main.yml` | Tasks executed by the prerequisites role |
| `roles/prereqs/handlers/main.yml` | Service reload/restart handlers for the prerequisites role |

### Hardening role

| Exact path | Function |
|---|---|
| `roles/hardening/defaults/main.yml` | Default variables for the hardening role |
| `roles/hardening/tasks/main.yml` | Tasks executed by the hardening role |
| `roles/hardening/handlers/main.yml` | Service reload/restart handlers for the hardening role |

Do not place all three files in one directory. Preserve the extracted directory tree exactly.
