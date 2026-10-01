# homelab-public

Small bootstrap and maintenance scripts for my homelab.

## Structure

- repo root: clone bootstrap helpers
- `scripts/nixos/`: NixOS setup
- `scripts/proxmox/`: Proxmox post-install and cluster recovery
- `scripts/windows/`: Windows setup
- `scripts/wsl/`: WSL setup

## Pull The Repo

Linux/macOS/WSL:

```bash
curl -fsSL https://raw.githubusercontent.com/ratrat64/homelab-public/main/clone-homelab-public.sh | bash
```

PowerShell:

```powershell
irm https://raw.githubusercontent.com/ratrat64/homelab-public/main/clone-homelab-public.ps1 | iex
```

Both commands install `git` if needed and clone the repo into `~/Git/homelab-public`.

## Fast-forward local main branches (Linux/systemd user)

Register individual checkouts, scan roots, or both; scans discover new nested checkouts on every run:

```bash
bash scripts/ubuntu/main-fast-forward.sh --repo ~/Git/project --repo ~/other/notes --scan ~/Git
```

Run the same command later to add repositories or scan roots. The updater and registration lists live in `~/.local/bin/main-fast-forward` and `~/.config/main-fast-forward/{repos,scans}`. The user timer runs every five minutes; inspect it with `systemctl --user status main-fast-forward.timer`, run once with `systemctl --user start main-fast-forward.service`, and see reports with `journalctl --user -u main-fast-forward.service`.

Only local `main` branches with a configured upstream are updated. Dirty `main` worktrees and divergent branches are skipped; branches not checked out in a worktree are advanced without changing files. To remove a registration, delete its line from `~/.config/main-fast-forward/repos` or `~/.config/main-fast-forward/scans`. To uninstall:

```bash
systemctl --user disable --now main-fast-forward.timer
rm ~/.config/systemd/user/main-fast-forward.service ~/.config/systemd/user/main-fast-forward.timer ~/.local/bin/main-fast-forward
rm -r ~/.config/main-fast-forward
systemctl --user daemon-reload
```
