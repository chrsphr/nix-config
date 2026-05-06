# nix-config

Personal NixOS configuration for all machines and services — managed as a single flake.

## Hosts

### Personal machines

| Host | Description |
|------|-------------|
| `chris-framework` | AMD Framework AI 300 laptop |
| `chris-desktop` | AMD desktop (gaming/workstation) |
| `chris-wsl` | Windows Subsystem for Linux |

### Servers / LXC containers (Proxmox)

| Host | IP | Role |
|------|----|------|
| `caddy` | 192.168.1.239 | Reverse proxy + TLS (Cloudflare DNS) |
| `pihole-1` | 192.168.1.9 | Primary DNS |
| `pihole-2` | 192.168.1.10 | Secondary DNS |
| `immich` | 192.168.1.127 | Photo management |
| `plex` | 192.168.1.209 | Media server |
| `transcode` | 192.168.1.74 | FFmpeg transcoding worker |
| `transmission` | 192.168.1.136 | Torrent client |
| `sonarr` | 192.168.1.75 | TV automation |
| `grafana` | 192.168.1.122 | Metrics dashboard |
| `uptime-kuma` | 192.168.1.31 | Uptime monitoring |
| `paperless` | 192.168.1.32 | Document management |
| `tailscale` | 192.168.1.207 | VPN exit node |
| `claude-agent` | 192.168.1.33 | Remote Claude Code agent |
| `mealie` | 192.168.1.34 | Recipe manager |
| `gb-grid` | 192.168.1.28 | GB power grid Postgres + BMRS ingester |

All host IPs and Caddy routing are defined in `hosts.nix` — the single source of truth for network topology.

---

## Rebuilding a machine

### Local rebuild (on the machine itself)

```bash
sudo nixos-rebuild switch --flake /home/chris/nix-config#<hostname>
```

For example, on the Framework laptop:

```bash
sudo nixos-rebuild switch --flake /home/chris/nix-config#chris-framework
```

### Remote deployment with deploy-rs

Remote deploys use [deploy-rs](https://github.com/serokell/deploy-rs). Deploy nodes are auto-generated from `hosts.nix` — any host that exists in both `hosts.nix` and `nixosConfigurations` gets a deploy node. All builds happen locally and closures are copied to the target.

Deploy all servers (shows a confirmation prompt first):

```bash
./deploy-all.sh
```

Deploy a single server:

```bash
deploy .#caddy
```

Dry run — preview what would change without activating:

```bash
./deploy-all.sh --dry-activate
deploy .#caddy --dry-activate
```

Rollback all servers:

```bash
./deploy-all.sh --rollback
```

deploy-rs includes **magic rollback** — if a deployment makes a machine unreachable (e.g. broken networking), it automatically rolls back after a timeout.

The `deploy` user has passwordless sudo configured on all servers. SSH key auth is required.

### Build only (no switch) — test for errors

```bash
nixos-rebuild build --flake /home/chris/nix-config#<hostname>
```

This builds the system closure without activating it. Useful for catching errors before deploying.

### Dry run with nixos-rebuild

```bash
nixos-rebuild dry-activate --flake /home/chris/nix-config#<hostname>
```

Shows which services would be restarted and what would change, without applying anything.

---

## Updating flake inputs

Update all inputs (nixpkgs, home-manager, etc.) to their latest versions:

```bash
nix flake update
```

Update a single input:

```bash
nix flake update nixpkgs
nix flake update nixpkgs-unstable
```

After updating, commit the new `flake.lock` before rebuilding:

```bash
git add flake.lock
git commit -m "Update flakes"
```

Then rebuild the relevant machines to apply the updates.

---

## Testing changes before deploying

### Build for a different host locally

You can build a remote host's configuration locally to catch errors without touching the target:

```bash
nixos-rebuild build --flake /home/chris/nix-config#<remote-hostname>
```

The build runs on your local machine but produces the configuration for the target host.

### Evaluate without building

Check that the Nix expressions parse and evaluate correctly:

```bash
nix eval .#nixosConfigurations.<hostname>.config.system.build.toplevel.drvPath
```

### Check the diff before switching

After a `nixos-rebuild build`, compare the new system with the currently running one:

```bash
nvd diff /run/current-system ./result
```

(`nvd` is the NixOS version diff tool — install with `nix-shell -p nvd` if not present.)

---

## Secrets management (sops-nix)

Secrets are encrypted with age and stored in `secrets/*.yaml`. Each host can only decrypt its own secrets using its SSH host key.

### Edit a secret

```bash
sops secrets/<name>.yaml
```

### Add a new secret file

1. Add the host's age public key to `.sops.yaml` under the appropriate creation rules.
2. Create and edit the file: `sops secrets/<name>.yaml`
3. Reference it in the host config via `config.sops.secrets.*`

### Rotate/re-encrypt secrets after adding a new host key

```bash
sops updatekeys secrets/<name>.yaml
```

---

## Repository structure

```
flake.nix                  # Flake inputs, NixOS configs, deploy-rs nodes
flake.lock                 # Pinned dependency versions
hosts.nix                  # Network topology — IPs, ports, Caddy routing
deploy-all.sh              # Deploy all servers (with confirmation prompt)
.sops.yaml                 # Age encryption rules per host

<hostname>.nix             # Top-level config for each host
hardware/                  # Hardware-specific configs (Framework, desktop)
modules/                   # Reusable NixOS modules
  common.nix               # Base for desktop machines (GNOME, Tailscale, etc.)
  cloudflare-tunnel.nix    # Cloudflare tunnel service wrapper
  nfs-home-automount.nix   # Smart NFS mount (WiFi/Tailscale aware)
  keyboard-backlight-timeout.nix  # Framework keyboard backlight
  locale.nix               # Locale/timezone
home/                      # Home Manager profiles
  common.nix               # Shared: Git, zsh, GNOME extensions
  framework.nix            # Framework-specific user packages
  desktop.nix              # Desktop-specific user packages
  wsl.nix                  # WSL: Python, 1Password SSH bridge
secrets/                   # sops-nix encrypted YAML files
common.nix                 # Base for all server/LXC containers
```

---

## Common workflows

### Add a new server

1. Create `<hostname>.nix` importing `common.nix` and any relevant modules.
2. Add the host to `flake.nix` under `nixosConfigurations`.
3. Add the host to `hosts.nix` with its IP (and `caddy = true` if it needs a reverse proxy entry).
4. If it needs secrets, add its age key to `.sops.yaml` and create `secrets/<hostname>.yaml`.
5. Boot the server with a NixOS installer, then deploy:

```bash
nixos-install --flake /home/chris/nix-config#<hostname>
```

Or deploy remotely after initial install:

```bash
deploy .#<hostname>
```

### Roll back a broken deployment

deploy-rs has **magic rollback** — if the machine becomes unreachable after activation, it rolls back automatically. To manually roll back:

```bash
deploy .#<hostname> --rollback
./deploy-all.sh --rollback
```

On the machine directly:

```bash
sudo nixos-rebuild switch --rollback
```

Or at boot: select a previous generation from the bootloader menu.

### Garbage collect old generations

```bash
sudo nix-collect-garbage -d
```

Automatic GC is configured on all hosts (weekly, removing generations older than 7–14 days).
