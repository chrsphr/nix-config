# LXC → container migration: Proxmox LXCs → NixOS containers on hutch

End state: every service that runs as a Proxmox LXC today runs as a
systemd-nspawn container on `hutch` (192.168.1.2), keeping its existing
LAN IP. Pairs with [nas-migration.md](nas-migration.md), which covers the
storage side (ZFS pool, NFS, TrueNAS retirement).

## How it's wired

- `lib/network.nix` — each migrating host keeps its IP and gains
  `parent = "hutch"`. That single field makes hutch declare a
  container for it. Caddy routing and Gatus monitors are untouched (IPs don't
  change, so both keep working through each cutover).
- `hosts/containers/<name>.nix` — the container config, mirroring
  `hosts/lxc/<name>.nix` (same services, same internal paths). Shared base is
  `hosts/containers/common.nix`.
- `hosts/hutch.nix` — per-container wiring: bind mounts, `enableTun`,
  the `cutoverPending` list (see below), and the
  `ConditionPathIsMountPoint=/mnt/Hutch/Media` guard on media containers so
  they can't start against an empty mount if the pool didn't import.
- The LXC definitions stay in `flake.nix` until each service is cut over, so
  the live LXCs remain deployable during the transition. `deploy .#<name>`
  still targets the LXC; the container rides along with `deploy .#hutch`.

**Nothing starts by itself.** Every container whose IP is still owned by a
live LXC is in the `cutoverPending` list in `hosts/hutch.nix`
(`autoStart = false`). Cutover = copy state → shut down the LXC → remove the
name from `cutoverPending` → `deploy .#hutch`.

Container root filesystems live at `/var/lib/nixos-containers/<name>/` on
hutch — service state copied there persists like the LXC's root disk did.

## Per-service state & secrets

State copy targets are relative to the container root, e.g. plex state goes to
`/var/lib/nixos-containers/plex/var/lib/plex/` on hutch.

| Service | State to copy from the LXC | Secrets bootstrap on hutch |
| --- | --- | --- |
| `caddy` | `/var/lib/caddy` (optional — DNS-01 re-issues the wildcard cert anyway) | `scp /home/deploy/.config/sops/age/keys.txt` → `/var/lib/sops-nix/caddy/keys.txt` |
| `pihole-1` / `pihole-2` | none required — config is fully declarative; gravity regenerates via the update timer. Optional: `/var/lib/pihole` (query history) | — |
| `plex` | `/var/lib/plex` (large; `rsync -aH`) | — |
| `sonarr` | `/var/lib/sonarr` **and** `/var/lib/prowlarr` (on the LXC the latter is a symlink to `/var/lib/private/prowlarr` — copy the real dir) | — |
| `transmission` | `/var/lib/transmission` | — |
| `tailscale` | `/var/lib/tailscale` (keeps the node identity; skip it and you re-auth + re-approve the exit node/routes in the admin console) | — |
| `uptime` | `/var/lib/gatus` (optional — uptime history) | copy `/etc/ssh/ssh_host_ed25519_key` → `/var/lib/sops-nix/uptime/ssh_host_ed25519_key` (secrets are encrypted to that key) |
| `gb-grid` | `/var/lib/postgresql`, `/var/lib/grafana`, `/var/lib/gb-grid` | copy `/var/lib/sops-nix/key.txt` → `/var/lib/sops-nix/gb-grid/key.txt` |
| `beeper` | `/var/lib/beeper` (bbctl login + bridge sessions — copying it means **no** re-login) | — |
| `immich` | per [nas-migration.md](nas-migration.md) — moves with the ZFS pool | per nas-migration.md |

Secrets dirs on hutch are created by tmpfiles (`/var/lib/sops-nix/<name>`,
mode 0700) and bind-mounted read-only to `/var/secrets` in the container.
Keep the copied keys `root:root 0600`.

## Cutover runbook (per service)

```bash
LXC=192.168.1.75          # the LXC's current IP
NAME=sonarr               # container/host name

# 1. Stop the service on the LXC (keeps state consistent while copying).
ssh deploy@$LXC 'sudo systemctl stop sonarr prowlarr'

# 2. Copy state into the container root on hutch (create dirs first —
#    the container has never started, so its root doesn't exist yet).
ssh deploy@192.168.1.2 "sudo mkdir -p /var/lib/nixos-containers/$NAME/var/lib"
rsync -aH --numeric-ids -e ssh --rsync-path='sudo rsync' \
  deploy@$LXC:/var/lib/sonarr/ \
  deploy@192.168.1.2:/var/lib/nixos-containers/$NAME/var/lib/sonarr/

# 3. Shut down the LXC (Proxmox: pct shutdown / the web UI).

# 4. Remove $NAME from cutoverPending in hosts/hutch.nix, then:
deploy .#hutch

# 5. Fix ownership from the host (uids inside the container differ from the
#    LXC's), then restart the service if it crash-looped meanwhile:
ssh deploy@192.168.1.2 "sudo nixos-container run $NAME -- chown -R sonarr:sonarr /var/lib/sonarr"
ssh deploy@192.168.1.2 "sudo nixos-container run $NAME -- systemctl restart sonarr"

# 6. Verify: the service on its usual IP, its Gatus check, and via Caddy.

# 7. Clean up the repo: drop nixosConfigurations.$NAME from flake.nix and
#    delete hosts/lxc/$NAME.nix.
```

Suggested order — low-risk and pool-independent first (media containers can't
start until the pool is attached, see nas-migration.md step 1; DNS and ingress
last because everything depends on them):

1. `uptime` → 2. `gb-grid` → 3. `beeper` → 4. `tailscale`
5. *(pool attached & verified)* `transmission` → `sonarr` → `plex`
6. `pihole-2` → `pihole-1` (one DNS server stays up throughout)
7. `caddy` (brief ingress blip; copy `/var/lib/caddy` to skip re-issuance)
8. `immich` — with the NAS cutover, per nas-migration.md

## Notes / caveats

- **RAM:** the full fleet at once (plex, immich, postgres+grafana, …) is much
  heavier than the LXCs were one-per-service — check `free -h` on hutch as
  cutovers proceed.
- **QSV/hardware transcode (plex, immich):** on baremetal there's no
  passthrough to arrange — if hutch's CPU has an Intel iGPU, `/dev/dri` is
  already on the host; enabling it is a bind mount + `allowedDevices` per
  container (commented-out snippet in `hosts/hutch.nix`). Until then both
  transcode on CPU (the userspace driver stack is already in the configs).
- **tailscale:** the container gets `/dev/net/tun` + `CAP_NET_ADMIN` via
  `enableTun` (already wired). IP-forward sysctls apply to the container's own
  network namespace.
- **caddy's `/srv/sites`:** the LXC has a Proxmox-side read-only NFS bind of
  `Media/Sites` at `/srv/sites`, but nothing in the current Caddyfile
  references it — not replicated in the container. If static sites come back,
  bind `/mnt/Hutch/Media/Sites` the same way plex's mounts work.
- **prowlarr** has no container of its own — it stays co-located with sonarr
  (same as on the LXC).
- After the **last** cutover: delete `hosts/lxc/` entirely and drop the
  `mkLxc`/`mkSopsLxc` helpers from `flake.nix`.
