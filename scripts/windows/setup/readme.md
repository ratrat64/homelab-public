# Windows post-install setup

Automated workstation provisioning after a fresh Windows install. Steps are defined as numbered scripts under `steps/`, orchestrated by `main.ps1`.

## How to use

```powershell
# Run interactively — prompts for which steps to execute
.\main.ps1

# Run specific steps
.\main.ps1 -Step winget,creds,nas-mounts

# Dry run — log what would happen without changing the system
.\main.ps1 -DryRun

# Bootstrap wrapper (warns if not elevated)
.\bootstrap.ps1 -Step winget,creds
```

## Directory layout

```
setup/
├── bootstrap.ps1      # Entry point; warns if not admin, delegates to main.ps1
├── main.ps1            # Orchestrator — loads libs, discovers steps, runs selected ones
├── lib/                # Shared library modules sourced by main.ps1
│   ├── config.ps1      # Read JSON manifests from data/
│   ├── logging.ps1     # Colored output helpers
│   ├── paths.ps1       # Resolve %USERPROFILE%, %APPDATA%, etc.
│   ├── process.ps1     # Run commands with error handling
│   └── prompts.ps1     # Interactive selection menus
├── steps/              # Numbered step scripts, each registered in main.ps1
│   ├── 01-winget.ps1       # Install winget packages
│   ├── 02-creds.ps1        # Pull secrets from NAS, clone repos
│   ├── 03-nas-mounts.ps1   # Map NAS shares to drive letters
│   ├── 04-winutil.ps1      # Run Chris Titus Windows Utility
│   ├── 05-shutup10.ps1     # Run O&O ShutUp10++
│   ├── 06-wsl.ps1          # Enable WSL and Windows features
│   ├── 07-docker.ps1       # Install Docker Desktop
│   ├── 08-app-config.ps1   # Deploy app configs from configs/
│   ├── 09-jobs.ps1         # Deploy scheduled jobs / helper scripts
│   └── 10-registry.ps1     # Apply registry tweaks
├── data/               # JSON manifests — the source of truth for each step
│   ├── app-configs.json     # App config file sources and destinations
│   ├── app-links.json       # Installer download URLs
│   ├── creds-map.json       # NAS path → local path mappings for secrets
│   ├── jobs.json            # Script deployment definitions
│   ├── nas-shares.json      # NAS share → drive letter mappings
│   ├── registry-changes.json# Registry key/value changes
│   └── repos.json           # Git repos to clone
├── configs/            # Version-controlled config files deployed by app-config step
│   ├── vscode/             # settings.json and extensions list
│   ├── terminal/           # Windows Terminal settings.json
│   ├── syncthing/          # config.xml.template
│   ├── mremoteng/          # confCons.xml.template
│   ├── obs-studio/         # plugins.json
│   ├── audacious/          # plugins.json
│   ├── opencode/           # config.toml
│   ├── winutil/            # Chris Titus profiles
│   ├── shutup10/           # O&O ShutUp10++ profiles
│   └── jobs/               # Helper scripts (e.g., robocopy-recordings.ps1)
├── installers/          # Installer definitions
│   ├── winget/             # JSON lists of winget package IDs
│   └── custom/             # PowerShell installer scripts (e.g., OBS plugins)
├── secrets/             # Runtime-only files pulled from NAS (not committed)
│   ├── templates/          # Expected file name stubs
│   └── README.md           # Instructions
└── docs/                # Supporting documentation
    ├── manual-steps.md
    └── recovery.md
```

## How it works

1. **`bootstrap.ps1`** checks for elevation, then calls `main.ps1` with any passed arguments.
2. **`main.ps1`** loads all library scripts from `lib/`, then dot-sources every step script from `steps/`. Each step script registers itself into the `$steps` array (name, description, handler).
3. If no `-Step` argument is given, the user is prompted to pick steps interactively.
4. Each selected step's handler is invoked in order.
5. Step logic is **data-driven** — it reads JSON manifests from `data/` rather than hardcoding values. To adjust behavior, edit the JSON, not the step script.

## Adding a new step

1. Create `steps/XX-name.ps1` following the existing pattern.
2. Add a `[pscustomobject]` entry to the `$steps` array in `main.ps1`.
3. If the step needs configuration data, add a JSON file in `data/`.
4. If it deploys config files, place them in `configs/`.

## Best practices

- Always run with `-DryRun` on an unfamiliar machine first.
- Never commit real secrets — use `secrets/templates/` to document expected file names.
- Prefer adding behavior through JSON manifests before writing custom scripts.
