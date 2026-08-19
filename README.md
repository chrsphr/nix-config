# nix-config

Personal NixOS configuration for all machines and services — managed as a single flake.

Decision records, incident history and pending work live in
[`docs/notes.md`](docs/notes.md); code comments point there with
`# why: docs/notes.md#<anchor>`.

## Hosts

### Personal machines

| Host | Description |
|------|-------------|
| `chris-framework` | AMD Framework AI 300 laptop |
| `chris-desktop` | AMD desktop (gaming/workstation) |
| `chris-wsl` | Windows Subsystem for Linux |

### Server + services

Two baremetal servers run every service as a systemd-nspawn container
(`hosts/containers/`). Each container keeps its own LAN IP on its host's `br0`
bridge, so it looks like a separate host on the network.

Both servers import `modules/container-host.nix`, which gives them the LAN
bond/bridge and declares one container per `lib/network.nix` host naming them
as `parent`. `hutch` additionally **is the NAS** (ZFS pool `Hutch`, NFS,
snapshots, encrypted B2 backup — `modules/nas.nix`); `minihutch` is compute
only.

Containers have no `nixosConfigurations` entry of their own — **deploying a
server deploys its containers with it**. The "On" column below says which.

| Host | IP | On | Role |
|------|----|----|------|
| `hutch` | 192.168.1.2 | — | Baremetal NAS + container host |
| `minihutch` | 192.168.1.3 | — | Baremetal container host (no storage). Install/cutover: `docs/minihutch-install.md` |
| `caddy` | 192.168.1.239 | minihutch | Reverse proxy + TLS (Cloudflare DNS) |
| `pihole-1` | 192.168.1.9 | hutch | Primary DNS |
| `pihole-2` | 192.168.1.10 | minihutch | Secondary DNS |
| `immich` | 192.168.1.127 | hutch | Photo management |
| `plex` | 192.168.1.209 | hutch | Media server |
| `transmission` | 192.168.1.136 | hutch | Torrent client |
| `sonarr` | 192.168.1.75 | hutch | TV automation |
| `prowlarr` | 192.168.1.75 | hutch | Indexer manager (co-located on sonarr host) |
| `uptime` | 192.168.1.31 | minihutch | Uptime monitoring (Gatus, declarative via `lib/network.nix`). LAN-only at `http://192.168.1.31:3001` — tunnel routing is pending (see `docs/notes.md`). |
| `tailscale` | 192.168.1.207 | minihutch | VPN exit node |
| `gb-grid` | 192.168.1.28 | hutch | GB power grid Postgres + BMRS ingester |
| `beeper` | 192.168.1.40 | minihutch | Self-hosted Beeper bridges (Signal, WhatsApp, Telegram, Bluesky) via bbctl. Outbound-only — no inbound/Caddy. Signal/WhatsApp from nixpkgs; Telegram and Bluesky are Go bridgev2 bridges built from pinned upstream releases. One-time `bbctl login` bootstrap required — see below. |

All host IPs and Caddy routing are defined in `lib/network.nix` — the single source of truth for network topology.

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

Remote deploys use [deploy-rs](https://github.com/serokell/deploy-rs). Deploy nodes are auto-generated from `lib/network.nix` — any host that exists in both `lib/network.nix` and `nixosConfigurations` gets a deploy node. In practice that is `hutch` and `minihutch`: the containers have no `nixosConfigurations` entry, so **deploying a server deploys every service on it**. All builds happen locally and closures are copied to the target.

Deploy the server:

```bash
deploy .#hutch
```

Dry run — preview what would change without activating:

```bash
deploy .#hutch --dry-activate
```

Magic rollback is **disabled** on this fleet (its confirmation SSH round-trip hung intermittently and triggered spurious rollbacks — see `docs/notes.md#magicrollback-disabled`). Verify a deploy by checking services afterwards; the server's physical console is the recovery path if an activation goes bad.

The `deploy` user has passwordless sudo configured. SSH key auth is required.

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

Secrets are encrypted with age and stored in `secrets/*.yaml`. Each host only holds the key that decrypts its own secrets; keys are provisioned out-of-band.

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

## Monitoring (Gatus)

The `uptime` host runs [Gatus](https://gatus.io). Monitor definitions live next to each host entry in `lib/network.nix`, so a single source of truth covers IP, port, Caddy routing, and uptime checks. `uptime.nix` is just a thin shell that calls `hostsLib.generateGatusEndpoints`.

### How to add or change a monitor

Add a `monitor` field to any entry in `lib/network.nix` — a single attrset or a list (for hosts needing multiple checks, e.g. v4 + v6 DNS):

```nix
immich = {
  ip = "192.168.1.127"; port = 2283; caddy = true;
  monitor = { type = "http"; path = "/api/server/ping"; group = "Hutch Primary Services"; };
};
```

The full schema (per-type fields, defaults, assertions) is documented in the
comment block at the top of `lib/network.nix`.

For checks that aren't tied to a host (e.g. probing external services), pass them via the `extra` argument in `uptime.nix`:

```nix
endpoints = hostsLib.generateGatusEndpoints {
  extra = [
    { name = "Internet Access"; url = "tcp://1.1.1.1:53";
      conditions = [ "[CONNECTED] == true" ]; interval = "60s"; }
  ];
};
```

### Authenticated checks (secrets)

For monitors that need credentials (e.g. an API token), put only the secret value in `secrets/uptime.yaml`, reference it from the monitor's `headers` in `lib/network.nix` via `${ENV_VAR}` interpolation, and render it into a `gatus.env` sops template wired to `services.gatus.environmentFile` in `hosts/containers/uptime.nix`. The non-secret prefix (user/realm/token-name) stays in `lib/network.nix`. No monitor currently needs this — git history has a worked example (the retired Proxmox token).

```bash
# Add or edit a secret
sops secrets/uptime.yaml

# Wire it: secrets.<name> = {} + sops.templates."gatus.env" + services.gatus.environmentFile
```

### Deploying changes

```bash
deploy .#uptime
```

Gatus reloads on activation. State (uptime history) lives in `/var/lib/gatus/data.db` (SQLite) and persists across deploys.

Pending work (e.g. tunnel routing for external access) is tracked in the
Pending section of `docs/notes.md`.

---

## Beeper bridges (`beeper`)

The `beeper` container on minihutch (192.168.1.40) self-hosts [mautrix](https://github.com/mautrix) chat bridges connected to a personal **Beeper** account. Config is in `hosts/containers/beeper.nix`.

### How it works

Each bridge runs on this box and dials **outbound** over a websocket to Beeper's hosted Matrix server (`matrix.beeper.com`); messages are then read in the normal **Beeper app** on any device. Consequences:

- **No inbound anything** — no Caddy entry, no Cloudflare tunnel, no port forwarding. The only listening port is SSH (admin via Tailscale/LAN). That's why `beeper` has just a port-22 Gatus monitor and no `caddy` flag in `lib/network.nix`.
- Self-hosting keeps your **third-party credentials/sessions** (WhatsApp link, Signal reg, etc.) on this box, never on Beeper. Message **content** can be end-to-bridge encrypted so Beeper stores only ciphertext; **metadata** still transits Beeper, and you trust their closed server.
- [`bbctl`](https://github.com/beeper/bridge-manager) (the Beeper Bridge Manager, `beeper-bridge-manager` in nixpkgs) handles provisioning + config generation against Beeper. Each bridge is a systemd service running `bbctl run --no-update --custom-startup-command <our binary> sh-<name>` — the `--custom-startup-command` flag makes bbctl launch **our** Nix-built binary instead of downloading one, so nothing non-Nix ever executes.

### Bridges and where each binary comes from

| Bridge | Source | Notes |
|--------|--------|-------|
| Signal | nixpkgs-unstable `mautrix-signal` (Go bridgev2) | |
| WhatsApp | nixpkgs-unstable `mautrix-whatsapp` (Go bridgev2) | |
| Telegram | **built from source** (`mautrix/telegram`, Go bridgev2) | Not in nixpkgs (which still ships the old Python 0.15.3). History: `docs/notes.md#beeper-bridges`. |
| Bluesky | **built from source** (`mautrix/bluesky`, Go bridgev2) | Not in nixpkgs. Both from-source bridges use the shared `mkMautrixBridge` helper (`tags = [ "goolm" ]`, pure-Go olm). |

The bridges are defined as a `name -> command` attrset in `hosts/containers/beeper.nix`; one systemd unit per entry is generated by `mkBridgeService`. Each unit has `ConditionPathExists = /var/lib/beeper/bbctl.json`, so it stays inactive (no fail-loop) until the one-time login below.

### One-time bootstrap (imperative)

State (the bbctl login token + each bridge's SQLite DB) lives in **`/var/lib/beeper/`** on the container, owned by the `beeper` system user. It is **not** in the repo or sops — back up that directory if you care about bridge history.

1. Log bbctl into the Beeper account (interactive — email + code):
   ```bash
   ssh deploy@192.168.1.40
   sudo -u beeper env HOME=/var/lib/beeper BBCTL_CONFIG=/var/lib/beeper/bbctl.json bbctl login
   ```
   This writes `/var/lib/beeper/bbctl.json`, which flips the `ConditionPathExists` and lets the services start.
2. Start them (they auto-start on every boot thereafter):
   ```bash
   sudo systemctl start mautrix-signal mautrix-whatsapp mautrix-telegram mautrix-bluesky
   ```
3. In the **Beeper app**, open/start a chat with each bridge bot and send `login`:
   - `@sh-signalbot` — scan the QR from Signal → Linked Devices
   - `@sh-whatsappbot` — scan the QR from WhatsApp → Linked Devices (or `login phone`)
   - `@sh-telegrambot` — phone number → code → 2FA password
   - `@sh-blueskybot` — handle + a Bluesky **app password** (bsky.app → Settings → App Passwords, *not* your main password)

### Deploying changes

The container rides along with the host: `deploy .#minihutch`. Magic rollback is disabled fleet-wide (see flake.nix), so verify by checking the `mautrix-*` services inside the container after a deploy.

### Adding a bridge

1. **In nixpkgs and Go bridgev2** (the easy case): add `name = "${pkgs.mautrix-<name>}/bin/mautrix-<name>";` to the `bridges` attrset and the package to `environment.systemPackages`.
2. **Not in nixpkgs** (e.g. bluesky): add a `buildGoModule` derivation pinned to an upstream tag with `tags = [ "goolm" ]`, then reference its binary. **Gotcha:** these bridges embed their version via `ldflags` — without `-X main.Tag=v<version>` they panic at startup (`invalid semver: unknown`). See the bluesky derivation.
3. Build, deploy, `systemctl start mautrix-<name>`, then `login` via `@sh-<name>bot` in the app.

> bbctl comes from nixpkgs-unstable (≥0.14 is required so telegram runs as a
> Go bridge). The 0.13-era patch/wrapper history is in
> `docs/notes.md#beeper-bridges`.

### Removing a bridge

1. Delete its entry from the `bridges` attrset (and `environment.systemPackages`), then deploy — activation stops and removes the systemd unit.
2. Optionally deregister it from Beeper (**destructive** — drops its rooms on Beeper). The confirm prompt needs a real terminal, so run it interactively:
   ```bash
   ssh -t deploy@192.168.1.40 'sudo -u beeper env HOME=/var/lib/beeper BBCTL_CONFIG=/var/lib/beeper/bbctl.json bbctl delete sh-<name>'
   ```

---

## Pi-hole adlists (`pihole-1`, `pihole-2`)

Blocklists are **state, not config**: they live in each container's
`/var/lib/pihole/gravity.db`, not in this repo.

`services.pihole-ftl.lists` is deliberately unset — setting it is what creates
`pihole-ftl-setup.service`, which re-POSTs every list to the FTL API on each
boot and fails there ("Database not available") on every single boot.
why: `docs/notes.md#container-one-offs`.

Both piholes currently carry one list (StevenBlack unified hosts, ~95k
domains). `pihole-gravity-update.timer` re-downloads and rebuilds gravity at
boot+10min and every 24h, so the lists stay fresh on their own.

Add or remove a list in the web UI (Adlists), or in SQL against
`gravity.db` (`docs/notes.md#container-one-offs` has the INSERT), then
rebuild gravity:

```bash
# on the parent server (hutch for pihole-1, minihutch for pihole-2).
# The bash -c wrapper is required: handing machinectl the pihole binary
# directly runs it but relays none of its output.
sudo machinectl shell pihole-1 /run/current-system/sw/bin/bash -c 'pihole -g'
```

Because the lists are state, a container rebuilt **from scratch** comes up
resolving but not blocking. Verify after any such rebuild:

```bash
dig +short doubleclick.net @192.168.1.9    # expect: 0.0.0.0, not an IP
```

## Repository structure

```
flake.nix                  # Flake inputs, host table (one line per machine), deploy-rs nodes
flake.lock                 # Pinned dependency versions
lib/network.nix            # Network topology — IPs, ports, Caddy routing, Gatus monitors
.sops.yaml                 # Age encryption rules per host

hosts/                     # One file per machine
  chris-framework.nix      # Framework laptop
  chris-desktop.nix        # Desktop (gaming/workstation)
  chris-wsl.nix            # WSL
  install-iso.nix          # Minimal SSH-enabled live installer ISO (build only)
  containers/              # NixOS containers — one per service, either server
    common.nix             # Shared base for every container
    caddy.nix              # Reverse proxy
    immich.nix             # Photo management
    ...
  hutch.nix                # Baremetal NAS + container host (192.168.1.2)
  minihutch.nix            # Baremetal container host, no storage (192.168.1.3)
hardware/                  # Hardware-specific configs incl. disko layouts
modules/                   # Reusable NixOS modules
  container-host.nix       # Container-host role: LAN bond/bridge + container generation
  nas.nix                  # NAS role: ZFS, NFS, sanoid, smartd, encrypted rclone->B2
  common-desktop.nix       # Base for desktop machines (GNOME, Tailscale, etc.)
  cloudflare-tunnel.nix    # Cloudflare tunnel service wrapper
  nfs-home-automount.nix   # Smart NFS mount (WiFi/Tailscale aware)
  keyboard-backlight-timeout.nix  # Framework keyboard backlight
  locale.nix               # Locale/timezone
  luks-tpm.nix             # LUKS root with TPM2 auto-unlock
  btrfs-maintenance.nix    # btrfs scrub + fstrim + store dedup (AC-gated)
  usbip-tuner.nix          # USB/IP export/attach for the DVB tuner
  keys.nix                 # SSH public keys
  container-snapshots.nix  # btrfs subvolumes + nightly snapshots for container roots
home/                      # Home Manager profiles
  common-home.nix          # Shared: Git, zsh, GNOME extensions
  framework.nix            # Framework-specific user packages
  desktop.nix              # Desktop-specific user packages
  wsl.nix                  # WSL: Python, 1Password SSH bridge
pkgs/                      # Local packages (network-optimizer + pinned deps)
docs/                      # notes.md (decisions/incidents/pending) + install runbooks
secrets/                   # sops-nix encrypted YAML files
```

---

## Common workflows

### Add a new service

Services run as containers on one of the two servers; there is no separate
machine to install. Pick `hutch` if it needs the media library or the iGPU,
`minihutch` otherwise.

1. Add the host to `lib/network.nix` with its IP and
   `parent = "hutch"` / `parent = "minihutch"` (plus `caddy = true` for a
   reverse proxy entry, and a `monitor` spec for Gatus). That one field is
   what makes that server declare a container for it.
2. Create `hosts/containers/<name>.nix` importing `./common.nix`.
3. Add any bind mounts or per-container extras to `containerHost.perContainer`
   in that server's `hosts/<parent>.nix`.
4. If it needs secrets, add its age key to `.sops.yaml`, create
   `secrets/<name>.yaml`, add the name to `containerHost.withSecrets` in
   `hosts/<parent>.nix`, and put the decryption key at
   `/var/lib/sops-nix/<name>/` on that server.
5. Deploy the parent:

```bash
deploy .#hutch        # or: deploy .#minihutch
```

**Moving a service between the two servers** is just changing `parent` — but
deploy the *old* parent first so it gives up the IP, then the new one, and
carry over any state under `/var/lib/nixos-containers/<name>/` plus the sops
key. `docs/minihutch-install.md` walks through this for the five services that
moved on 2026-08-09.

### Roll back a broken deployment

Magic rollback is disabled on this fleet, so roll back manually:

```bash
deploy .#hutch --rollback
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
