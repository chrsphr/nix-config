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

Container-host topology (modules/container-host.nix):

    physical NICs ─► bond0 (active-backup) ─► br0 (host IP) ◄─ container veths

EVERY physical ethernet port is a bond0 slave, matched by `Type=ether` rather
than by name — adding a PCI card can renumber enpXsY, and new ports should
just become extra uplink paths. bond0 is br0's single uplink; br0 owns the
host IP and containers attach via hostBridge. active-backup means exactly one
NIC carries traffic and the rest are hot standbys: whichever cable is plugged
in Just Works, failover on link loss is ~100ms (MII monitor), and a switching
loop is impossible even with both NICs cabled to the same switch.

If a future NIC must NOT be an uplink (dedicated 10G to another box, say),
give it its own systemd.network unit sorting before "20-lan-port" with a
narrower match — first match wins. `networking.bridges/bonds` are not used
because they want fixed port-name lists, defeating the catch-all match.

#### No STP

STP is off on br0 because active-backup bonding already makes loops
impossible — and because STP was tried first on hutch and caused LAN-wide
instability: the bridge's random low MAC won root-bridge election against the
UniFi kit, and every container veth start/stop forced 30s listening/learning
plus topology-change FDB flushes — intermittent multi-second blackholes of
established TCP. Do not turn it back on.

#### Fixed bridge MAC

bond0 and br0 get a fixed MAC (normally the onboard NIC's) so the machine's
LAN identity never changes across boots, failovers or cable moves. Without
it the bridge adopts the lowest port MAC — and container veths get random
ones, so br0's (and the host IP's) MAC would change whenever a container with
a low MAC starts or stops.

### Storage and NAS

#### TrueNAS takeover

hutch took over from the TrueNAS "lilnas" VM (retired 2026-08-08). The two 8TB
disks moved into the hutch chassis and pool "Hutch" (guid 5739333095810664970)
was imported in place — never reformatted — so dataset properties and snapshots
came with it. `modules/nas.nix` settings were derived from TrueNAS's config
export:

- Scrub: TrueNAS ran Sunday 00:00, threshold 35 days → `autoScrub` monthly.
- Snapshots: TrueNAS periodic task on Hutch/Media (non-recursive), daily at
  midnight, 2-week retention, schema `auto-%Y-%m-%d_%H-%M` → sanoid daily=14.
- NFS: TrueNAS had NFSv3+v4, no network restriction. Media exports with
  mapall chrsphr:root (all clients squashed to uid 3000); Backups no squash.
  `192.168.0.0/16` because chris-framework mounts over WiFi from 192.168.4.x.
- Cron/init scripts: `powertop --auto-tune` (daily + postinit) →
  `powerManagement.powertop`; powersave governor (postinit) →
  `powerManagement.cpuFreqGovernor`; SMART short (Wed 00:00) / long
  (1st 04:00) → `services.smartd`.
- Users: UIDs preserved so NFS ownership survived the move — chrsphr uid 3000
  (home /mnt/Hutch/Chris), hutch uid 3001 (nologin, file ownership),
  admin uid 950 skipped (NixOS root covers it).

#### forceImport removal

`forceImportAll`/`forceImportRoot` were needed for the first import only, when
the disk labels still carried TrueNAS's hostId. Both disks' labels now read
hostid a8f3c1d2 / hostname "hutch" (verified 2026-08-08 with `zdb -l`), so a
normal import succeeds and the multi-host safety checks are back on. Don't
reintroduce them: if an import ever fails, find out why first.

`forceImportRoot = false` must stay set explicitly — it defaults to true and
only flips to false in NixOS 26.11, so dropping the line would leave the
force-import in place while looking like it had been turned off.

#### ZFS ARC

Reclaim tuning, deliberately NOT a cap (`zfs_arc_max` stays 0): ARC should
still be free to use most of the box when nothing else wants the memory; what's
tuned is how readily it gives it back.

Symptom this fixes (observed 2026-08-09, 64G box): during the nightly
rclone→B2 run, ARC sat at ~45 GiB with an 86/14 MRU:MFU split — the backup
streaming the whole media library had filled the cache with data read exactly
once. Meanwhile ~2 GiB of live service memory had been pushed to swap
(gb-grid 686M, immich 464M, network-optimizer 149M). Paying disk latency on
running services to cache bytes nothing will re-read is the wrong trade.

`zfs_arc_sys_free=8589934592` is a floor on FREE SYSTEM MEMORY, not a ceiling
on ARC: ARC grows into whatever is idle but backs off to keep 8 GiB free, so it
yields ahead of demand instead of after reclaim has already swapped something
out. 8 GiB ≈ peak container + rclone footprint (~12 GiB) with headroom, and
still leaves ARC ~45 GiB when the box is quiet. Settable live for testing:
`echo 8589934592 > /sys/module/zfs/parameters/zfs_arc_sys_free`.

Two related knobs, checked and deliberately left alone:

- `zfs_arc_shrinker_limit` — historically THE cause of this symptom (throttled
  ARC to ~39 MiB freed per reclaim call). Already 0 in ZFS 2.4.
- `zfs_arc_shrinker_seeks` — relative eviction cost; default 2 means ARC is
  already twice as evictable as page cache. Drop to 1 if 8 GiB proves tight.

`vm.swappiness=10`: stock 60 tells the kernel anon memory is fair game, which
is why the squeeze landed on running services rather than ARC. 10 keeps swap a
genuine last resort while making eviction the first answer.

#### B2 backup design

Replaced the TrueNAS-era cloudsync tasks (plain `rclone copy` of Photos and
Backups, unencrypted, Tue/Wed 00:00). Three changes:

1. Everything goes through an rclone `crypt` remote — contents AND
   names/directories encrypted locally; B2 stores opaque blobs and never sees
   the key.
2. `sync`, not `copy` — the bucket mirrors current on-disk state instead of
   accumulating everything ever written (hence the delete guards).
3. Credentials come from sops (secrets/hutch.yaml), not a hand-written
   rclone.conf.

The crypt passwords are ALSO in 1Password ("backblaze hutchv2"). Losing both
them and secrets/hutch.yaml makes every byte in B2 permanently unreadable —
B2 cannot help; that is the point of client-side encryption.

Bucket setup NOT expressed in nix (done by hand in the B2 console): bucket
`hutch-v2`, private, app key scoped to just that bucket; lifecycle
keepDaysAfterHide=30, keepDaysAfterUpload=null. That lifecycle rule IS the
undo window — `hard_delete = false` turns removals into "hidden" versions the
rule holds for 30 days. Without it a bad sync is final.

Unit design: ordered after sops-nix because a Persistent timer can fire at
boot before the template is rendered; `ConditionPathIsMountPoint` because if
the pool didn't import, `/mnt/Hutch/Media` is an empty directory and `rclone
sync` from empty sources would delete the entire remote; oneshot with
`TimeoutStartSec=infinity` because the ~4TB first seed runs for days against a
90s default; each rclone call is individually guarded because NixOS job
scripts run under `set -e` and one path failing (transient B2 error, a
`--max-delete` trip) must not skip the rest. hutch decrypts with its own SSH
host key, so the default /run/secrets tmpfs is fine — the host re-runs
activation at boot (unlike the containers, see
[Secrets under /var](#secrets-under-var)).

#### SMB dormant

TrueNAS had SMB shares defined (netbios HUTCH, workgroup WORKGROUP) but the
CIFS service itself was DISABLED — only nfs+ssh were enabled. The share
definitions are kept in nas.nix for parity with `enable = false`; flip it on
if SMB is ever actually wanted.

#### NAS power tuning

hutch is an i5-12600K (Alder Lake) doing NAS work; the stock desktop power
envelope is far more than it needs. Checked and deliberately skipped:

- RAPL package power limits (PL1 135W / PL2 150W): left at stock on purpose.
- `scsiLinkPolicy`: both 8TB drives are already at med_power_with_dipm; only
  empty ports sit at keep_firmware_settings — forcing ALPM buys nothing.
- HDD spindown (`hdparm -B/-S`): plex/sonarr/transmission/sanoid touch Media
  continuously — the drives would thrash, not idle.

Package C-states are capped at PC2 by HARDWARE, not config (verified
2026-08-08 with turbostat/lspci): the 82599 10G NIC at 01:00.0 supports only
ASPM L0s, not L1, and Alder Lake needs every PCIe link in L1 for PC3+. Cores
reach CC7, iGPU RC6 works, NVMe L1 is on, MSR 0xE2 is unlimited — the NIC is
the sole blocker, costing ~1-2W at the package (~2.7W RAPL idle as-is). The
only fix is a NIC that supports L1; there is no software knob.
**Don't re-investigate.**

#### Thermald and smartd

thermald: Alder Lake's hybrid P/E topology — Intel's daemon handles it better
than the kernel's passive throttling alone.

cpu-epp oneshot: EPP is the one knob `cpuFreqGovernor="powersave"` does NOT
set — under intel_pstate active mode the governor picks the algorithm, EPP
biases within it. Stock balance_performance → balance_power is a measurable
idle saving with no impact on this workload. Ordered after powertop so
auto-tune can't clobber it; non-fatal because the sysfs file is absent unless
intel_pstate is active with HWP.

smartd: matched by WWN because udev's by-id name format isn't stable across
kernels (ata-HUH728080ALE601_<SERIAL> vs ata-<SERIAL>) and device letters
move. `-d sat` because smartd can't autodetect the device type on hutch's
controller, but explicit SATA passthrough works (verified with
`smartctl -d sat -i/-H`).

### Backups and snapshots

#### Container snapshot design

modules/container-snapshots.nix: btrfs subvolumes + nightly crash-consistent
snapshots for the nspawn container roots (both container hosts). Container
roots live at /var/lib/nixos-containers/<name> inside the btrfs /root
subvolume. Two pieces:

1. systemd.tmpfiles `v` rules declare each container root as a btrfs
   subvolume. Type `v` creates the subvolume if the path doesn't exist and
   does nothing if it does — idempotent desired-state, not a mutation script.
   tmpfiles-setup runs Before=sysinit.target while containers start via
   machines.target→multi-user.target, so subvolumes exist before any
   container starts, including first boot. Containers added later get theirs
   at the next boot (or `sudo systemd-tmpfiles --create`). The
   nixos-containers preStart only does `mkdir -p` (a no-op afterwards), and
   container@.service already carries RequiresMountsFor on the root.
2. container-snapshot.{service,timer} — nightly read-only snapshot of each
   subvolume into /snapshots/containers/<name>/, keeping the newest 14
   (mirrors sanoid daily=14 on Hutch/Media). Snapshots are atomic COW ⇒
   crash-consistent, like a power cut: sqlite (gatus) and postgres (immich)
   both recover from that on start. No container downtime.

Timing: 03:00, after sanoid's midnight ZFS snapshots. The 01:00 rclone→B2 run
can overlap — fine, different disks (NVMe roots vs the ZFS pool).
Persistent=true so a missed run fires at next boot.

Scope: Media is NOT in the container roots — bind-mounted from ZFS, covered
by sanoid + B2. /var/lib/sops-nix/<name> is tiny but not captured (see
Pending). Snapshots sit on the same NVMe as the live roots: this is rollback,
not backup — off-disk copy is a follow-up (see Pending).

#### Btrfs maintenance

Scrub weekly, not monthly: ConditionACPower can skip an occurrence outright,
and a condition failure still counts as the timer having fired — so
Persistent=true does NOT re-run a skipped occurrence, it waits for the next.
A shorter interval bounds how long a scrub can go missed: one skip costs a
week, not a month. Scrub is read-only, no extra write wear.

ConditionACPower exists because a scrub is a full-device read (10+ min of
sustained NVMe + CPU on the laptop) and fstrim is equally pointless unplugged;
it's a no-op on the desktop (no battery = on AC). It must go in `unitConfig`,
not `serviceConfig` — it's a [Unit] directive and systemd silently ignores it
in [Service].

`discard=async` (disko) handles TRIM at free-time; the weekly fstrim timer is
belt-and-braces and also covers /boot vfat, which doesn't do async discard.

### USB-IP and kernel pin

#### usbip tuner design

Why USB/IP exists: the Xbox One Digital TV Tuner (045e:02d5, dib0700 +
Panasonic MN88472, DVB-T/T2) is plugged into minihutch, but Plex — which
reads DVB tuners straight off /dev/dvb — runs in a container on hutch. USB
doesn't cross machines, so minihutch exports the device and hutch imports it,
after which /dev/dvb/adapter0 appears on hutch as if local.

    minihutch                              hutch
    ─────────                              ─────
    usbip-host driver ─► usbipd :3240 ═══► vhci-hcd ─► /dev/dvb/adapter0
    (device leaves the                                  │
     local DVB stack)                                   └─► plex container

The tradeoff this encodes: binding to usbip-host DETACHES the device from
minihutch's own DVB stack — /dev/dvb disappears there. The tuner belongs to
exactly one host at a time, and that host is hutch.

Caveats worth knowing before debugging at 1am:

- DVB is a real-time bulk-transfer workload; over USB/IP it's sensitive to
  LAN hiccups — dropouts show up as recording glitches, not errors.
- Both hosts must run the SAME kernel version (see [Kernel pin](#kernel-pin))
  — the usbip userspace is kernel-matched (`boot.kernelPackages.usbip`).
- There is no NixOS module for usbip, hence the hand-rolled units.
- The attach side is a long-running supervisor loop, not a oneshot: the
  attachment dies whenever the server reboots, the dongle is replugged, or
  the LAN blips, and nothing else would notice. Re-checking every 30s makes
  recovery automatic instead of a manual `usbip attach` after every
  minihutch deploy.
- usbipd has no authentication whatsoever — anyone who can reach tcp/3240 can
  claim the device — so `allowFrom` pins it to hutch's IP.

#### Kernel pin

hutch pins `linuxPackages_6_18`: ZFS 2.4.3's newest compatible kernel in
nixpkgs is 6.18 (`zfs.latestCompatibleLinuxPackages` = 6.18.x; nixpkgs
default `linuxPackages` is currently also 6.18.x, latest is 7.1.x).

minihutch deliberately has NO pin — no ZFS there — and tracks the nixpkgs
default. Today both resolve to the same 6.18.44, which is what USB/IP
requires; when the nixpkgs default kernel moves past 6.18, minihutch diverges
from hutch and the tuner attach breaks until they're re-aligned (tracked in
Pending). Bump hutch's pin when ZFS supports a newer kernel.

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

Pre-bond history, kept so it doesn't get "fixed" back (modules/container-host.nix):
br0 previously held .2 while its only port (enp1s0) was unplugged, with enp3s0
separately holding a DHCP .124. br0 still came up (container veths give the
bridge carrier, so `ConfigureWithoutCarrier=false` does not stop it), and its
connected 192.168.1.0/24 route at metric 0 beat enp3s0's DHCP route at metric
1024 — so every packet to the LAN, including SSH replies arriving on enp3s0,
was routed into a bridge with no cable and dropped. Raising the *default*
route metric to 2000 never helped: LAN traffic uses the connected route. The
arp_ignore/arp_filter sysctls that followed were treating symptoms (and
arp_filter additionally stopped .124 answering ARP at all, since the route
lookup for the sender kept returning br0). One L3 identity on the subnet
makes all of it unnecessary — hence the bond+bridge design.

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
