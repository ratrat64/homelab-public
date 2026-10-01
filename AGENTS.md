# Repository notes

- This is a collection of host-setup scripts, not a single app: Windows provisioning lives in `scripts/windows/setup/`, Proxmox recovery in `scripts/proxmox/cluster-fix/`, Proxmox post-install in `scripts/proxmox/post-install/`, and WSL/NixOS bootstraps in their respective directories. Scripts can install packages, alter host settings, or fetch credentials; use syntax checks and targeted dry runs rather than running setup on a development host.
- No repo-wide build, test, lint, CI, or package manager is configured. For a changed Bash script, use `bash -n path/to/script.sh`; PowerShell setup has a non-mutating step listing: `pwsh -File scripts/windows/setup/main.ps1 -ListSteps` (requires `pwsh`).
- For `scripts/ubuntu/main-fast-forward.sh`, run `bash scripts/ubuntu/test-main-fast-forward.sh`: it uses temporary local Git remotes and mocks `systemctl`, so it does not install a user timer.

## Windows setup

- `scripts/windows/setup/main.ps1` loads `lib/*.ps1`, dot-sources numbered `steps/*.ps1`, then dispatches through its explicit `$steps` registry. A new step needs both a script and a registry entry. `bootstrap.ps1` only warns about missing elevation; it does not elevate.
- Inspect steps with `pwsh -File scripts/windows/setup/main.ps1 -ListSteps`; target one with `pwsh -File scripts/windows/setup/main.ps1 -Step winget -DryRun`. `-NonInteractive` selects **all** available items when prompting would otherwise occur; `-Step` limits setup steps, not packages within a step. `-DryRun` is not perfectly read-only: the `creds` step creates its clone-root directory before checking it.
- Step data lives in `data/*.json`, deployed files in `configs/`, installer lists in `installers/`. `data/name.local.json` **replaces**, rather than merges with, `data/name.json` via `lib/config.ps1`; local data/config overrides and `secrets/runtime/` are gitignored. The `creds` step only lists NAS credential mappings (SMB pull is not implemented).
- `scripts/windows/setup/docs/README.md` uses the stale path `scripts/windows/windows-setup/`; use `scripts/windows/setup/` for commands.

## Proxmox / other bootstraps

- `scripts/proxmox/cluster-fix.sh` delegates to `cluster-fix/main.sh` and requires root on a Proxmox node; it changes quorum, removes a node, and restarts services. `scripts/wsl/wsl-setup/main.sh` must run as a non-root user and fetches its sub-scripts from GitHub rather than local copies. `scripts/nixos/setup.sh` requires `nix-shell` (packages specified in its shebang).
- `scripts/proxmox/post-install/main.sh` fetches `scripts/proxmox/setup/post-install-args.sh` from GitHub, but the tracked file is `scripts/proxmox/post-install/post-install-args.sh`; check/fix that URL before using the wrapper.
