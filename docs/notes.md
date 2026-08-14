# Engineering notes

Extracted rationale, history, and pending work for this flake. Code comments
say *what*; this file says *why*. Pointers in code look like
`# why: docs/notes.md#<anchor>`. Heading text is stable — anchors are
referenced from code, so append new headings rather than renaming old ones.

## Decisions

### Flake and deploy

#### Shared pkgs-unstable

#### Single-platform deployChecks

#### magicRollback disabled

#### Deploy ordering and sshd probe

### Networking

#### bond0 to br0

#### No STP

#### Fixed bridge MAC

### Storage and NAS

#### TrueNAS takeover

#### forceImport removal

#### ZFS ARC

#### B2 backup design

#### SMB dormant

#### NAS power tuning

#### Thermald and smartd

### Backups and snapshots

#### Container snapshot design

#### Btrfs maintenance

### USB-IP and kernel pin

#### usbip tuner design

#### Kernel pin

### Containers

#### Beeper bridges

#### Secrets under /var

#### Network optimizer

#### Container one-offs

### Hosts

#### Framework power tuning

#### Desktop

#### Hutch

#### Minihutch

## Incident history

### 2026-08-09 container migration hutch to minihutch

### 2026-07-27 wifi powersave latency

### 2026-07-12 hibernate crash

### 2026-07-03 magicrollback lockout

### br0 blackhole

### ssh identity mixup

## Pending

- [ ] **snapshots**: off-disk copy of container snapshots (→ /mnt/Hutch/Backups → B2); fold in /var/lib/sops-nix/<name> when added (modules/container-snapshots.nix)
- [ ] **desktop**: re-enable capSysNice when nixpkgs#524488 lands (workaround for nixpkgs#523200) (hosts/chris-desktop.nix)
- [ ] **home**: unpin darktable from stable once unstable's gflags static/dynamic conflict is fixed (home/common-home.nix)
- [ ] **framework**: recheck amd_hfi/ITMT core ranking after kernel bumps — look for sched_itmt_enabled (hosts/chris-framework.nix)
- [ ] **framework**: NVMe runtime-PM benefit unproven — check runtime_suspended_time after a few hours; drop the rule if still 0 (hosts/chris-framework.nix)
- [ ] **framework**: restore suspend-then-hibernate + HibernateDelaySec once crash fixed upstream (see [2026-07-12 hibernate crash](#2026-07-12-hibernate-crash))
- [ ] **framework**: charge cap 90% — bump to 100 before a trip (hosts/chris-framework.nix)
- [ ] **uptime**: replace reused laptop master sops key with a dedicated uptime key + re-encrypt (hosts/containers/uptime.nix)
- [ ] **beeper**: drop bbctl PUT-proxy patch when fixed upstream; bbctl >=0.14 needs on-box config regen (hosts/containers/beeper.nix)
- [ ] **usbip**: kernel-version coupling — hutch pinned 6.18, minihutch tracks nixpkgs default; usbip breaks if they diverge (see [Kernel pin](#kernel-pin))
- [ ] **nas**: B2 bucket lifecycle + app-key scoping configured by hand in the B2 console — document or automate; check if restores misbehave (modules/nas.nix)
- [ ] **nas**: drop zfs_arc_shrinker_seeks to 1 if the 8 GiB sys-free floor proves too tight (modules/nas.nix)
- [ ] **gatus**: route uptime.mcneill.fyi through the Cloudflare tunnel to Gatus:3001 — currently LAN-only
- [ ] **network-optimizer**: InfluxDB onboarding is manual/one-time; not set up: OpenSpeedTest sidecar, WAN steering, proxy features (hosts/containers/network-optimizer.nix)
