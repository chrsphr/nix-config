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

The two baremetal servers are probed (Gatus) on sshd:22 rather than a service
port: neither runs anything HTTP on the host itself, and sshd being up is
what distinguishes "the box is alive" from "a container on it died" — the
container-level monitors already cover the latter.

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

Self-hosted Beeper bridges (hosts/containers/beeper.nix, on minihutch).
Outbound-only: no Caddy vhost, no tunnel, no open ports. State (bbctl login
token + bridge DBs) in /var/lib/beeper; the README covers the one-time login
bootstrap. If /var/lib/beeper is restored from a previous box
(`chown -R beeper:beeper` after), the ConditionPathExists gate flips
immediately and no `bbctl login` is needed — the gate exists so units don't
fail-loop before the bootstrap.

Bridge provenance and quirks:

- **signal, whatsapp**: Go bridgev2 binaries straight from nixpkgs.
- **telegram**: as of v26.04 (calver tag v0.26xx.0) the bridge is a Go
  bridgev2 rewrite that speaks /provision/v3 and reports remote-connection
  state to the app. nixpkgs still ships only the old Python 0.15.3, so it's
  built from the upstream tagged release. The Go bridge auto-migrates the
  Python DB/config in place on first start
  (cmd/mautrix-telegram/legacymigrate.{go,sql}).
- **bluesky**: Go bridgev2, not packaged in nixpkgs — built from the upstream
  tagged release (pure-Go `goolm`, no libolm/CGO).
- **Upgrading a from-source bridge**: bump `version` + BOTH hashes (src and
  vendorHash).
- **ldflags Tag**: the bridges embed their version; without a valid tag they
  panic at startup ("invalid semver: unknown") converting version to calver.
- **bbctl PUT-proxy patch**: bbctl 0.13.0 runs sh-telegram in "python bridge"
  mode (Beeper still classifies sh-telegram as the legacy Python bridge
  server-side), holding the appservice websocket itself and proxying
  provisioning requests to the bridge's local HTTP listener. Its proxy
  hardcodes PUT for every proxied request (proxyWebsocketRequest in
  cmd/bbctl/proxy.go), so GET /v3/capabilities, /v3/whoami etc. fail with 405
  and the Telegram network never appears in the app. The overlay patches the
  proxy to forward the real method. Still unfixed in bbctl main as of
  2026-08; bbctl ≥0.14 treats telegram as a Go bridge and skips the proxy,
  but that path requires regenerating the on-box config — so patch rather
  than upgrade (tracked in Pending).
- **`-m` wrapper**: because bbctl classifies sh-telegram as Python, it
  launches the custom command python-style (`<cmd> -m mautrix_telegram -c
  config.yaml`). The Go binary rejects `-m`, so a thin wrapper strips the
  leading `-m <module>` and forwards the rest.
- **libolm**: the mautrix bridges pull in olm-3.2.16, which nixpkgs flags
  insecure/unmaintained; permitted because it's required for end-to-bridge
  encryption.
- `--custom-startup-command` disables all bbctl downloads — nothing non-Nix
  ever runs.

#### Secrets under /var

Containers that decrypt sops secrets write them to paths under /var
(e.g. /var/lib/sops/<name>), NOT the default /run/secrets: /run is tmpfs and
containers don't re-run activation at boot, so files under /run are wiped on
every reboot and never recreated until the next host deploy. /var lives on
the container's persistent btrfs subvolume. (The hosts themselves are fine
with /run/secrets — they do re-run activation at boot.)

uptime's key story: the original per-host key was lost with the hardware it
lived on. uptime.yaml is also encrypted to the laptop master key, so a copy
of that key is used instead (see .sops.yaml). Tradeoff: the laptop master
key lives on the server too — a compromise of that box decrypts every sops
secret. Acceptable for the homelab; a dedicated key is tracked in Pending.

#### Network optimizer

Network Optimizer for UniFi, built from source via pkgs/network-optimizer.nix
— upstream ships no prebuilt Linux tarball of the web app (only the Windows
MSI and the optional multi-site agent).

- UniFi controller creds are entered in the UI, stored encrypted in SQLite.
- InfluxDB 2 (co-located) backs Monitoring; no declarative provisioning in
  NixOS — onboard once via its UI on :8086 (admin user + all-access token),
  paste the token into the app's Monitoring wizard. State in
  /var/lib/influxdb2 inside the container root, so nightly btrfs snapshots
  cover it.
- `DOTNET_RUNNING_IN_CONTAINER=true` makes the app keep ALL state (SQLite,
  encrypted creds, data-protection keys, floor plans, exports) in /app/data,
  matching upstream's docker layout — nothing writes under the read-only,
  store-resident app dir. It also skips UseHttpsRedirection/HSTS, correct
  behind Caddy.
- `AmbientCapabilities=CAP_NET_RAW` for ping/traceroute probes; must NOT be
  combined with NoNewPrivileges — execve clears the ambient set.
- Deliberately not set up: OpenSpeedTest sidecar (:3005), WAN Steering daemon
  (single-WAN here), self-hosted Traefik/nginx proxy features (Caddy already
  fronts the UI).

pkgs/network-optimizer.nix build notes: Blazor-ApexCharts comes from a local
NuGet feed special case; MinVer is overridden (no git metadata in the nix
build); Grpc.Tools ships glibc binaries needing autoPatchelf; tools/ contains
the speed-test helpers.

#### Container one-offs

- **common.nix — default gateway**: hostBridge puts the container straight on
  the LAN, but without a default route it can't reply to (or reach) anything
  off-subnet.
- **common.nix — useHostResolvConf off**: the container profile defaults it
  on, so resolvconf inside the container regenerates /etc/resolv.conf from
  the HOST's copy — the systemd-resolved stub (127.0.0.53), and resolved
  doesn't run inside the containers: every lookup fails (caddy: "lookup
  acme-v02.api.letsencrypt.org: no such host"). Off means the container's own
  networking.nameservers are written instead.
- **pihole — resolver must not be 127.0.0.1**: pihole-ftl-setup curls
  ftl.pi-hole.net during boot before pihole-ftl (the port-53 listener) is up,
  so a 127.0.0.1 resolver deadlocks the boot; container@ times out
  (TimeoutStartSec=1min) and restarts forever. Cloudflare upstreams instead.
- **transmission — chroot sandbox dropped**: the module's RootDirectory +
  MountAPIVFS sandbox can't be set up inside nspawn — MountAPIVFS makes
  systemd stage /run/host/.os-release-stage/, but /run/host belongs to nspawn
  and is read-only in the container, so the unit dies with 226/NAMESPACE.
  The container is the isolation boundary anyway.
- **tailscale — extraSetFlags mirrors extraUpFlags**: extraUpFlags only runs
  on first login (autoconnect skips an already-authenticated node), so it
  can't be the source of truth — a manual `tailscale up
  --advertise-exit-node` had already clobbered the subnet route once.
  extraSetFlags reapplies on every activation; keep the two lists identical.
  No `--accept-routes`: this node advertises its own LAN, and accepting
  tailnet routes back would invite a loop.
- **immich — uid 3000**: the library was historically written over NFS with
  mapall chrsphr:root, so every existing file is uid 3000; immich matches it
  (nspawn shares the host's uid space) to stay consistent with
  desktop/framework NFS access. The media-mount guard lives on the host:
  container@immich won't start unless /mnt/Hutch/Media is mounted.
- **immich — accelerationDevices**: the default [] sets PrivateDevices and
  blocks all device access; QSV needs the render node visible in the unit's
  sandbox.
- **gb-grid — password oneshot**: applies the sops postgres password to the
  gb_grid role on each boot; idempotent, so rotating is just
  `sops secrets/gb-grid.yaml` + redeploy. pg_hba overridden to require
  scram-sha-256 from LAN clients.

### Hosts

#### Framework power tuning

The battery-tuning notebook behind hosts/chris-framework.nix:

- **U-APSD on** (`iwlwifi uapsd_disable=0`): trigger-based Wi-Fi power save on
  the Intel AX210 (swapped in for the stock MT7925). Bitmask: 3 = disabled on
  BSS+P2P (driver default), 0 = enabled. Lowers idle radio power; revert to 3
  if the AP misbehaves (latency spikes, disconnects on power-save negotiation).
- **NM wifi.powersave OFF**: tried and reverted — see
  [2026-07-27 wifi powersave latency](#2026-07-27-wifi-powersave-latency).
  U-APSD is deliberately kept on: the more selective mechanism, some
  idle-power benefit without that cost.
- **No amd_prefcore param**: tried, confirmed no-op — amd-pstate isn't the
  preferred-core mechanism on Krackan Point; amd_hfi is, and it binds
  (AMDI0104:00) but nothing feeds core ranking to the scheduler:
  `sched_itmt_enabled` doesn't exist, cpu_capacity is uniform 1024 across all
  16 CPUs, no amd_hfi kernel messages — despite CONFIG_SCHED_MC_PRIO=y +
  CONFIG_AMD_HFI=y and a clearly hybrid topology (amd_pstate_highest_perf
  alternates 196/135). sched_itmt_enabled only appears once a driver calls
  sched_set_itmt_support(), so this is an upstream driver gap. Recheck after
  kernel bumps (tracked in Pending).
- **ABM off** (no `amdgpu.abmlevel`): content-adaptive (not ambient) backlight
  management; level 3 caused visible flicker/brightness drift on changing
  content. Stable with it off. Level 1 (barely perceptible) is the option if
  the battery saving is ever worth revisiting.
- **PSR re-enabled** (`amdgpu.dcdebugmask=0x0`): nixos-hardware's
  framework-amd-ai-300-series module disables Panel Self-Refresh via
  dcdebugmask=0x10 for historical panel flicker, but on this kernel/Mesa PSR
  is reliable and saves ~1W on static content. The host's param lands after
  nixos-hardware's on the cmdline, so last-wins re-enables it. Revert to 0x10
  on any internal-panel flicker/corruption.
- **Lazy RCU** (`rcu_nocbs=all`, `rcutree.enable_rcu_lazy=1`): offload and
  batch non-urgent RCU callbacks to cut idle wakeups; used by ChromeOS,
  reported as a measurable win on the Framework AMD battery-tuning thread.
- **No powertop auto-tune**: it blanket-enables USB autosuspend (input-device
  stutter after idle) and re-applies knobs power-profiles-daemon then manages
  differently — ppd owns runtime power policy.
- **Targeted PCI runtime PM** (udev rule, nvme driver only): the NVMe comes up
  with power/control=on and never idles its link. Scoped by driver so USB is
  untouched and ppd keeps owning the rest; amdgpu excluded — `on` is correct
  for an iGPU. No iwlwifi rule: tried, and the driver overrides it — udevadm
  confirms the rule writes "auto" but the AX210 reports
  runtime_enabled=forbidden with runtime_usage=2; iwlwifi holds PM references
  and doesn't support PCI runtime PM on this device (d0i3 removed years ago).
  NVMe benefit unproven (tracked in Pending).
- **localsearch off**: GNOME's indexer re-scans on every large tree change
  (nix-config checkouts, builds) for a search feature unused here. Filename
  search in Files still works; full-text does not.
- **avahi off**: constant idle wakeups for little benefit. Trade-off: no
  .local resolution or printer/cast auto-discovery — re-enable if the NFS
  automount or printing starts relying on mDNS.
- **Audio codec power save** (`snd_hda_intel power_save=1`): revert to 0 if
  clicking sounds occur.
- **Charge cap 90%** (framework_laptop EC): extends cycle life. Bump before a
  trip: `echo 100 | sudo tee /sys/class/power_supply/BAT1/charge_control_end_threshold`.
- **Hibernate disabled** — see [2026-07-12 hibernate crash](#2026-07-12-hibernate-crash).
- **Journal capped 500M**: was 2.1 GB uncapped — steady write amplification on
  compressed btrfs, working against the dirty_writeback batching sysctl.
- **Docker socket-activated** (`enableOnBoot = false`): dockerd is only wanted
  inside the gb-grid dev shell. Containers with `--restart=always` won't
  survive a reboot under this — flip back to true if ever needed.

#### Desktop

- Hibernate resumes from the btrfs swapfile inside LUKS; `resume_offset` is
  the physical offset from `btrfs inspect-internal map-swapfile`.
- Rusticl OpenCL: `RUSTICL_ENABLE=radeonsi` is useless without the ICD, so
  `mesa.opencl` is shipped too — the loader (ocl-icd, used by darktable)
  finds it under /run/opengl-driver.
- Sunshine comes from unstable: nixpkgs lags upstream badly (stable AND
  unstable sat on 2025.924 for months; nixpkgs#524668), so `nix flake update`
  picks up newer builds without moving the host off stable.
- Sunshine `ConditionUser=chris`: autoStart wires the user unit to
  graphical-session.target, which the GDM greeter session (user gdm-greeter)
  also reaches — Sunshine launched there first, grabbed port 48010, and the
  real login's instance failed to bind ("RTSP server ... Address already in
  use").
- No cpu-epp oneshot (unlike hutch): GNOME's power-profiles-daemon already
  sets balance_performance on the default profile and re-asserts it on
  changes.

#### Hutch

- The TV tuner lives on minihutch (no free/reachable port on hutch), but Plex
  reads DVB straight off /dev/dvb, so it's projected over USB/IP and passed
  into the plex container (see [usbip tuner design](#usbip-tuner-design)).
- iGPU transcode (plex + immich): the i5-12600K's UHD 770 renderD128 is
  exposed by bind mount + allowedDevices — no passthrough gid mapping to
  arrange. The userspace half (intel-media-driver, vpl-gpu-rt, video/render
  groups) lives in the two container configs; the host needs no
  hardware.graphics of its own since each nspawn guest builds its own
  /run/opengl-driver. Without those lines both apps silently transcode on
  CPU. Verify with `vainfo` inside each container — it should report the iHD
  driver and H264/HEVC VLD+encode entrypoints.
- `char-DVB` (major 212) rather than individual frontend0/demux0/dvr0 nodes:
  those only exist while the tuner is attached, and DeviceAllow entries for
  absent paths are dropped at unit-load time — naming them would silently
  deny access on every boot where plex started before the tuner did.
- Media mount guard: containers reading the library are gated on
  ConditionPathIsMountPoint so they can't start against an empty dir if the
  pool didn't import — nspawn would happily bind an empty host dir.
  `mkMerge`, not `//`, because plex appears in both attribute sets and `//`
  would silently drop the guard.
- plex ExecStartPre `mkdir -p /dev/dvb`: nspawn refuses to start when a
  bindMount source is missing, and /dev/dvb only exists while the tuner is
  attached. tmpfiles (preCreate) covers boot but races on deploy —
  switch-to-configuration restarts container@plex and
  systemd-tmpfiles-resetup concurrently, which is exactly how it failed the
  first time. ExecStartPre is ordered by construction and keeps Plex
  independent of whether minihutch is up.
- Keys-only SSH states BOTH `PasswordAuthentication=false` and
  `KbdInteractiveAuthentication=false`: with UsePAM the latter would
  otherwise *advertise* a keyboard-interactive path (blocked only by pam_deny
  in the sshd PAM stack). Stating both makes keys-only unambiguous. (Same on
  minihutch.)
- users.chris has no password option on purpose: uid 1001 matches the account
  from first setup; the password set via chpasswd on the live box survives
  rebuilds and stays out of the repo. Add initialHashedPassword if it ever
  needs to be declarative. (Same on minihutch, where the shared uid also
  keeps the two boxes agreeing over NFS/rsync.)

#### Minihutch

- Role: second baremetal container host, same shape as hutch (container-host
  module) but compute only — no ZFS, no NFS, no B2, no nas.nix, no media
  bind mounts. Runs beeper, caddy, pihole-2, tailscale, uptime.
- Hardware facts (MAC 10:02:b5:86:02:0a for the onboard enp2s0/igc NIC) were
  read off the live ISO on the actual box, 2026-08-09. The box also has WiFi
  (wlp1s0, rtw89); bond slaves match on Type=ether and WiFi is Type=wlan, so
  it is never enslaved.
- Tuner export: binding to usbip-host hands the device to hutch entirely —
  minihutch's own /dev/dvb goes away; fine, nothing local uses it. usbipd is
  unauthenticated, so allowFrom pins it to hutch's IP.
- caddy + uptime decrypt with age keys placed by hand at
  /var/lib/sops-nix/<name>/keys.txt (NOT in the repo) —
  docs/minihutch-install.md step 7.

## Incident history

### 2026-08-09 container migration hutch to minihutch

beeper, caddy, pihole-2, tailscale and uptime moved from hutch to the new
minihutch box (installed the same day; see docs/minihutch-install.md). caddy
and uptime took their sops key requirement with them. minihutch's disk
previously held minimox's Proxmox ZFS root (pool "rpool", 6 LXC subvolumes),
wiped deliberately at install. The wider context: lilnas (TrueNAS VM, .12)
and minimox (Proxmox, .30) were retired 2026-08-08 and hutch took over both
roles — see git history if either ever comes back.

### 2026-07-27 wifi powersave latency

`networking.networkmanager.wifi.powersave = true` enabled 2026-07-27,
reverted 2026-07-30 — it caused latency spikes surfacing as randomly slow
page loads. A sleeping radio can only wake on a beacon (beacon int 100 ≈
102ms), and a page load is a chain of serialized round trips (DNS, SYN, TLS)
that each pay that wait. Measured against the router (one hop, no DNS):
sparse `ping -i 1` avg 31ms/max 112ms vs continuous `ping -i 0.02` avg
1.9ms/max 6ms; with powersave off, sparse drops to avg 1.9ms/max 3.5ms.
Signal was never the issue (-59 dBm, HE-MCS 7/9, 0% loss). To re-test:
compare sparse vs continuous ping to the router — jitter that vanishes under
load is power save, not DNS or the ISP.

### 2026-07-12 hibernate crash

Hibernate disabled on the Framework 2026-07-12: resume-from-hibernate
corrupts amdgpu's TTM LRU bulk-move state, hard-locking the machine on a
later GPU submission (ttm_lru_bulk_move_tail oops / list_del corruption in
amdgpu_cs_ioctl). 16 identical crashes since suspend-then-hibernate was
enabled 2026-05-29, across kernels 7.0.10 through 7.1.3 — an upstream amdgpu
bug, not a kernel regression. pstore dumps: /var/lib/systemd/pstore/.
Restore suspend-then-hibernate + HibernateDelaySec once fixed upstream
(tracked in Pending).

### 2026-07-03 magicrollback lockout

deploy-rs magic rollback's confirmation SSH hung intermittently on this fleet
— immich, caddy and sonarr all hit it 2026-07-03. Activation itself succeeded
every time, then the confirm round-trip stalled and triggered a spurious
rollback; one interrupted run left beeper half-activated with sshd down.
`magicRollback = false` since then (flake.nix); deploys are verified by
checking services, and hutch's physical console is the recovery path if an
activation ever goes bad.

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

The 1Password SSH agent holds both personal and work keys and offered the
work one first, which can't push to chrsphr repos. Fix (home/common-home.nix):
pin github.com to the personal key — `identitiesOnly` + the public key on
disk make the agent use only that identity. Desktop + Framework only; WSL
bridges 1Password differently and is left untouched.

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
