# nix-config

Personal NixOS configuration for all machines and services — managed as a single flake.

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
| `uptime` | 192.168.1.31 | minihutch | Uptime monitoring (Gatus, declarative via `lib/network.nix`). External access via Cloudflare tunnel is **TODO** — currently only reachable on the LAN at `http://192.168.1.31:3001`. |
| `tailscale` | 192.168.1.207 | minihutch | VPN exit node |
| `gb-grid` | 192.168.1.28 | hutch | GB power grid Postgres + BMRS ingester |
| `beeper` | 192.168.1.40 | minihutch | Self-hosted Beeper bridges (Signal, WhatsApp, Telegram, Bluesky) via bbctl. Outbound-only — no inbound/Caddy. Signal/WhatsApp are Go bridgev2 binaries; Telegram is the nixpkgs Python bridge (Beeper's `sh-telegram` is Python) launched via a small wrapper; Bluesky is the Go bridge built from a pinned upstream release. One-time `bbctl login` bootstrap required; see `hosts/containers/beeper.nix`. |

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

Magic rollback is **disabled** on this fleet (its confirmation SSH round-trip hung intermittently and triggered spurious rollbacks — see the comment in `flake.nix`). Verify a deploy by checking services afterwards; the server's physical console is the recovery path if an activation goes bad.

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

Add a `monitor` field to any entry in `lib/network.nix`. It can be a single attrset or a list (for hosts that need multiple checks, e.g. v4 + v6 DNS):

```nix
immich = {
  ip = "192.168.1.127"; port = 2283; caddy = true;
  monitor = {
    type = "http";                    # "http" | "dns" | "port"
    name = "Immich";                  # optional, defaults to host key
    path = "/api/server/ping";        # http only, default "/"
    group = "Hutch Primary Services"; # optional Gatus group
    # interval = "60s";               # default
    # scheme = "https";               # default https if host.https else http
    # insecure = true;                # skip TLS verify (self-signed certs)
    # url = "https://...";            # full URL override
    # headers.Authorization = "Bearer ...";  # may reference ''${ENV_VARS}''
  };
};

pihole-1 = {
  ip = "192.168.1.9"; port = 80; caddy = true;
  monitor = [
    { type = "dns"; name = "Pihole 1";      family = "v4"; group = "Hutch Primary Services"; }
    { type = "dns"; name = "Pihole 1 (v6)"; family = "v6"; group = "Hutch Primary Services"; }
  ];
};
```

Per-type fields:

- **http** — `scheme`, `path`, `insecure`, `headers`, `url` (override). Asserts `[STATUS] == 200`.
- **dns** — `resolver` (default = host IP), `query` (default `google.com`), `family` (`v4`/`v6`). Asserts `[DNS_RCODE] == NOERROR`.
- **port** — `targetPort` (default = host port). TCP connect; asserts `[CONNECTED] == true`.

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

For monitors that need credentials (e.g. an API token), put only the secret value in `secrets/uptime.yaml`, reference it from the monitor's `headers` in `lib/network.nix` via `${ENV_VAR}` interpolation, and render it into a `gatus.env` sops template wired to `services.gatus.environmentFile` in `hosts/containers/uptime.nix`. The non-secret prefix (user/realm/token-name) stays in `lib/network.nix`. No monitor currently needs this — see git history for the retired Proxmox token as a worked example.

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

### Known TODO

- **Cloudflare tunnel / external access** — the host has the cloudflare-tunnel module wired up, but the dashboard at `uptime.mcneill.fyi` is not yet routed to Gatus's port (3001) on the tunnel side. Currently LAN-only.

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
| Signal | nixpkgs `mautrix-signal` (Go bridgev2) | |
| WhatsApp | nixpkgs `mautrix-whatsapp` (Go bridgev2) | |
| Telegram | **built from source** (`mautrix/telegram`, Go bridgev2) via a thin wrapper | Not in nixpkgs (which still ships the old Python 0.15.3). Since v26.04 the bridge is a Go bridgev2 rewrite. Pinned to an upstream calver tag via `buildGoModule` with `tags = [ "goolm" ]`; auto-migrates the old Python DB in place on first start. bbctl still classifies `sh-telegram` as Python server-side, so it launches the command as `-m mautrix_telegram -c config.yaml`; the Go binary rejects `-m`, so `telegramCmd` strips the leading `-m <module>` and forwards `-c config.yaml`. |
| Bluesky | **built from source** (`mautrix/bluesky`, Go bridgev2) | Not in nixpkgs. Pinned to an upstream tag via `buildGoModule` with `tags = [ "goolm" ]` (pure-Go olm, no libolm/CGO). |

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

> Note: Beeper's registry still classifies `sh-telegram` as the Python bridge, so bbctl invokes the command python-style as `-m mautrix_telegram -c config.yaml`. `--custom-startup-command` runs our Go binary regardless, but the Go binary rejects the `-m` flag — hence the `telegramCmd` wrapper strips the leading `-m <module>` before forwarding `-c config.yaml`. The Go bridge migrates the legacy Python DB in place on first start.
>
> The same Python classification also means bbctl runs `sh-telegram` with its own **appservice-websocket→HTTP proxy** (`needsWebsocketProxy`, unlike the Go bridges which hold the websocket themselves). bbctl 0.13.0's proxy hardcodes `PUT` for every proxied request (`proxyWebsocketRequest` in `cmd/bbctl/proxy.go`), which breaks every provisioning API call the app makes (`GET /v3/capabilities`, `GET /v3/whoami`, …) with 405 — symptom: **Telegram never appears under Settings → Networks** even though messages bridge fine. `beeper.nix` therefore patches bbctl to forward the real method (`bbctl-patched`); still unfixed in bbctl `main` as of 2026-08. If bbctl is ever bumped to ≥0.14 (which treats Telegram as Go bridgev2 and drops the proxy), the on-box `config.yaml` must be regenerated instead of patched around — delete `/var/lib/beeper/.local/share/bbctl/prod/sh-telegram/config.yaml` and restart the unit, then re-`login`.

### Removing a bridge

1. Delete its entry from the `bridges` attrset (and `environment.systemPackages`), then deploy — activation stops and removes the systemd unit.
2. Optionally deregister it from Beeper (**destructive** — drops its rooms on Beeper). The confirm prompt needs a real terminal, so run it interactively:
   ```bash
   ssh -t deploy@192.168.1.40 'sudo -u beeper env HOME=/var/lib/beeper BBCTL_CONFIG=/var/lib/beeper/bbctl.json bbctl delete sh-<name>'
   ```

---

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
  containers/              # NixOS containers — one per service, either server
    common.nix             # Shared base for every container
    caddy.nix              # Reverse proxy
    immich.nix             # Photo management
    ...
  hutch.nix                # Baremetal NAS + container host (192.168.1.2)
  minihutch.nix            # Baremetal container host, no storage (192.168.1.3)
hardware/                  # Hardware-specific configs (Framework, desktop, servers)
modules/                   # Reusable NixOS modules
  container-host.nix       # Container-host role: LAN bond/bridge + container generation
  nas.nix                  # NAS role: ZFS, NFS, sanoid, smartd, encrypted rclone->B2
  common-desktop.nix       # Base for desktop machines (GNOME, Tailscale, etc.)
  cloudflare-tunnel.nix    # Cloudflare tunnel service wrapper
  nfs-home-automount.nix   # Smart NFS mount (WiFi/Tailscale aware)
  keyboard-backlight-timeout.nix  # Framework keyboard backlight
  locale.nix               # Locale/timezone
  container-snapshots.nix  # btrfs subvolumes + nightly snapshots for container roots
home/                      # Home Manager profiles
  common-home.nix          # Shared: Git, zsh, GNOME extensions
  framework.nix            # Framework-specific user packages
  desktop.nix              # Desktop-specific user packages
  wsl.nix                  # WSL: Python, 1Password SSH bridge
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
