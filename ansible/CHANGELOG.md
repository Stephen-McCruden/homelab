# Changelog

## 1.0.0-rc2 - 2026-07-10

- Corrected SSH host-key reconciliation comparison so unchanged keys report `ok`.
- Added an idempotent preflight to disable Fedora/systemd OSC 3008 shell-context output before Ansible fact gathering.
- Added persistent hardening and verification for the OSC 3008 compatibility setting.
- Preserved the fully converged Fedora Kubernetes node baseline and zero-change remote second run.
