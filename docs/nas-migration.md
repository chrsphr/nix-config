# NAS migration: TrueNAS VM → NixOS on hutch (baremetal)

End state: one baremetal NixOS host (`hutch`, 192.168.1.2) that both **is
the NAS** (ZFS pool `Hutch`, NFS, snapshots, B2 offsite sync) and **runs the
services** as NixOS containers. The TrueNAS VM (lilnas, 192.168.1.12, VMID
100) goes away, as do the Proxmox LXCs (see docs/lxc-migration.md).

The two physical 8TB disks move into the hutch chassis and the existing pool
is imported in place — no reformatting, no data copy.

## Why

- TrueNAS config → declarative NixOS: `modules/nas.nix` is the whole NAS,
  derived from the config export (`lilnas-25.10.5-20260806203849.db`,
  gitignored — contains secrets).
- immich today reads its library over an NFS loopback: Proxmox host mounts
  `192.168.1.12:/mnt/Hutch/Media` via NFS, then bind-mounts it into the LXC.
  Once storage and containers share a host, that's just a bind mount of the
  local dataset — no NFS in the path.

## What changed in the config

| Piece | File | Notes |
| --- | --- | --- |
| NAS stack | `modules/nas.nix` | ZFS import, scrub, sanoid, NFS, rclone→B2, smartd, users. Imported by `hosts/hutch.nix`. |
| immich container | `hosts/containers/immich.nix` | Mirror of `hosts/lxc/immich.nix`; same internal paths (`/mnt/media/Photos`), same `secrets/immich.yaml`, so library + DB carry over untouched. |
| Container wiring | `hosts/hutch.nix` | `containers.immich`: bind mounts + `autoStart = false` until cutover; `container@immich` has `ConditionPathIsMountPoint=/mnt/Hutch/Media` so it can't start against an empty library. |
| Network registry | `lib/network.nix` | `immich` now has `parent = "hutch"`. |

TrueNAS → NixOS mapping (all in `modules/nas.nix`):

- Pool `Hutch` import → `boot.zfs.extraPools` + `forceImportAll` (pool is
  owned by the TrueNAS hostId; drop the force flags after first boot).
- Media/Backups NFS shares → `services.nfs.server.exports`, same squash
  semantics (`Media` mapall → uid 3000, `Backups` unsquashed). Exports opened
  to `192.168.0.0/16` (TrueNAS had no restriction; framework mounts from the
  192.168.4.x WiFi VLAN).
- Snapshot task (Hutch/Media daily, 2-week retention) → `services.sanoid`.
- Scrub (Sun 00:00, 35-day threshold) → `services.zfs.autoScrub` monthly.
- B2 cloudsync (Photos Wed 00:00, Backups Tue 00:00, both COPY) →
  `rclone copy` oneshots + timers. COPY mode never deletes at the destination.
- SMART short Wed / long 1st-of-month → `services.smartd`, disks matched by
  serial (VKHWUELX, VKHNN8PX).
- powertop cron + powersave governor init scripts → `powerManagement.*`.
- Users chrsphr (uid 3000) / hutch (uid 3001) preserved so NFS ownership
  survives the move.
- SMB: shares existed in TrueNAS but the service was disabled — config kept
  for parity, still disabled.

## Cutover runbook

1. **Install the disks.** Physically move the two 8TB drives into the hutch
   chassis. Until this happens, `zfs-import-Hutch`, `nfs-server` and `smartd`
   fail on boot — harmless, the host still boots and containers keep running.
2. **Verify the pool imported:** `zpool status Hutch`, check datasets mounted
   under `/mnt/Hutch/`. Confirm the smartd by-id paths (`ls /dev/disk/by-id/`)
   — adjust `modules/nas.nix` if the new machine presents different names.
   Baremetal, so SMART reads the disks natively.
3. **B2 credentials.** The app key in the TrueNAS DB is encrypted and not
   portable. Write `/var/lib/rclone/rclone.conf` (mode 0600) with a fresh
   `b2` remote, then test: `systemctl start rclone-photos-backup`.
4. **immich age key.** Copy `keys.txt` from the LXC's
   `/home/deploy/.config/sops/age/keys.txt` into `/var/lib/sops-nix/immich/`
   on hutch (bind-mounted to `/var/secrets` in the container).
5. **Copy immich state** from the LXC: stop immich on the LXC, copy
   `/var/lib/immich` (database/config — *not* the media, that comes with the
   pool) to the container's `/var/lib/immich` on the host
   (`/var/lib/nixos-containers/immich/var/lib/immich`), preserving ownership.
6. **Flip immich:** shut down the LXC, remove `immich` from the
   `cutoverPending` list in `hosts/hutch.nix`, deploy hutch. Verify
   https://immich.mcneill.fyi (cloudflare tunnel token is the same secret).
   Then remove `immich` from `nixosConfigurations` (the LXC definition) and
   delete `hosts/lxc/immich.nix`.
7. **Repoint NFS clients** — desktop fstab and `modules/nfs-home-automount.nix`
   hardcode `192.168.1.12`. Either update them to the hutch IP, or add
   `192.168.1.12/24` as a secondary address on `br0` and change nothing.
8. **Decommission TrueNAS** once everything checks out; clean up the `lilnas`
   entry in `lib/network.nix` (caddy/monitor references).

## Caveats / open items

- **QSV:** the LXC got `/dev/dri` via Proxmox device passthrough. On hutch
  (baremetal) there's nothing to pass through — if the CPU has an Intel iGPU,
  `/dev/dri` is already on the host; exposing it to the immich/plex containers
  is a bind mount + `allowedDevices` (commented-out snippet in
  `hosts/hutch.nix`). Until then both transcode on CPU.
- **sops for rclone:** the B2 secret is a plain root-only file for now;
  TODO in `modules/nas.nix` to move it into sops once hutch has its own
  age key enrolled in `.sops.yaml`.
- **immich uid:** the container pins `users.users.immich.uid = 3000` so files
  it writes match the ownership the NFS mapall produced (chrsphr). nspawn
  shares the host's uid space, so the host sees them as `chrsphr` too.
- **Don't start the immich container before cutover** — its IP
  (192.168.1.127) is still owned by the live LXC. The `autoStart = false`
  + mount-point guard are the seatbelts, not a license.
