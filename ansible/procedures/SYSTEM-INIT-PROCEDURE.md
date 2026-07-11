# System Initialization Procedure

## Controller prerequisites

- Terraform-created Fedora nodes are reachable.
- The controller SSH private key matches `inventory/group_vars/all.yml`.
- Ansible Core 2.16 or newer is installed.

## Run

```bash
cd /home/stoof/GitHub/homelab/ansible
ansible-inventory --graph
ansible-playbook playbooks/system-init.yml --syntax-check
ansible-playbook playbooks/system-init.yml
ansible-playbook playbooks/system-init.yml
```

The first run converges fresh nodes. The second run should report `changed=0` for managed nodes.

## DNF behavior

The repository intentionally contains no explicit `dnf5 makecache --refresh` command. Package transactions refresh required metadata themselves. Cache deletion occurs only after a failed package transaction.

## Fedora OSC 3008 warning

Fedora 44/systemd may append OSC 3008 markers to output from commands executed through sudo. Ansible currently reports those markers as `Module invocation had junk after the JSON data`. This is an upstream interaction and does not mean a role printed output. The baseline does not weaken PAM, enable root SSH, or alter system login accounting merely to hide the warning.

## Fedora DNF5 transaction protection

The package-manager role disables `dnf-makecache.timer`, stops active automatic
metadata jobs, and waits for package-manager processes to exit before installing
packages. This avoids a Fedora 44 DNF5 race in which simultaneous makecache and
package transactions can leave cached RPM payloads unreadable during signature
validation. Package transactions are serialized across nodes and the cache is
removed only after a real transaction failure.
