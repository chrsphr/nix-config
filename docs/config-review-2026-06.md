# nix-config review — June 2026

Full review of the flake, all 14 LXC services, the three devices (framework,
desktop, WSL), shared modules, home-manager, disko layouts, and the sops/deploy
setup.

Overall it's a well-structured config: `hosts.nix` as a single source of truth
driving Caddy and Gatus generation is genuinely nice, the immich NFS mount
guard is thoughtful, and the disko/LUKS/TPM setup is clean.

**Highest-value quick wins: #1, #2, #7, #8, #11 — all small diffs.**

---

## Security

### 1. Cloudflare tunnel token leaks via process arguments
`modules/cloudflare-tunnel.nix:22` passes the token as `--token "$(cat …)"`,
so it's visible in `/proc/<pid>/cmdline` to every process on the host.
cloudflared reads `TUNNEL_TOKEN` from the environment — use
`serviceConfig.EnvironmentFile` (or systemd `LoadCredential`) instead.
Easiest fix: have sops render a `TUNNEL_TOKEN=…` template like the existing
`gatus.env` template on uptime.

### 2. Transmission RPC is wide open
`lxc/transmission.nix:23-25` binds to `0.0.0.0` with both whitelists disabled
and no authentication. Anyone on the LAN (or anything compromised on it) can
add torrents, change the download dir, or exfiltrate via the RPC. The module
supports `services.transmission.credentialsFile` for
`rpc-username`/`rpc-password`, or at minimum re-enable `rpc-host-whitelist`
scoped to the Caddy host.

### 3. All LXCs are privileged
`lxc/common-lxc.nix:29` sets `proxmoxLXC.privileged = true` for every
container. Plex/transcode plausibly need it for GPU passthrough and
immich/transmission/sonarr for the NFS bind mounts, but pihole, caddy, uptime,
beeper, tailscale (works unprivileged with a `/dev/net/tun` device entry), and
gb-grid don't obviously. A privileged LXC escape is root on the Proxmox host.
Converting requires recreating containers, so do it opportunistically — but
new containers shouldn't default to privileged. Move `privileged = true` out
of the common module into the hosts that need it.

### 4. `require-sigs = false` + `sandbox = false` on every LXC
`common-lxc.nix:16-17`. `require-sigs = false` means the nix daemon accepts
any unsigned closure from anyone who can reach the store. Since deploy-rs
pushes as the `deploy` user (who has passwordless sudo anyway) this is mostly
belt-removal without benefit: the cleaner pattern is generating a signing key
on the build machine and adding its public key to
`nix.settings.trusted-public-keys` on targets. `sandbox = false` only matters
when building *on* the containers — deploy-rs builds locally on the laptop,
so it's likely dead config that can be dropped.

### 5. npiperelay downloaded unverified at activation
`home/wsl.nix` fetches the *latest* GitHub release over the network during
home-manager activation with no checksum, then a systemd service executes it
with access to the 1Password SSH agent. Pin it: `pkgs.fetchzip` with a fixed
version and hash, so Nix verifies it and updates are deliberate.

### 6. Pi-hole admin password hash committed
`pihole-common.nix:42` — it's a balloon hash so not directly reversible, but
it's offline-crackable if the repo is or becomes public. Worth moving into
sops alongside the other secrets.

---

## Correctness / reliability

### 7. Dead ordering: `systemd.services.unbound.before = [ "pihole.service" ]`
`pihole-common.nix:132` — the unit is `pihole-ftl.service`, so this ordering
does nothing. Pi-hole can come up before unbound and serve SERVFAILs briefly.
Fix the name (and consider `wants`/`after` from pihole-ftl's side instead).

### 8. Missing NFS-mount guards on transmission and sonarr
Immich-server has `ConditionPathIsMountPoint` specifically so it can't run
against a missing NFS mount, but transmission writes to
`/mnt/media/Downloads` with no such guard. If the bind mount is absent it will
happily fill the container rootfs (and sonarr will import into a void). Apply
the same condition to `transmission.service` and `sonarr.service`.

### 9. Inconsistent static-IP handling
pihole-1/2, sonarr, transmission, tailscale, uptime, beeper, and gb-grid use
`mkStaticNetwork`, but **caddy** (the single most load-bearing service),
immich, plex, and transcode rely on DHCP with `useDHCP = lib.mkDefault true`,
even though `hosts.nix` declares their IPs and the deploy targets / Caddy
backends depend on them. If a router reservation is lost, deploys and the
whole `*.mcneill.fyi` proxy break. Use `mkStaticNetwork` everywhere a host has
an entry in `hosts.nix`.

### 10. The valkey overlay defeats the binary cache
`common-lxc.nix:97-101` — `overrideAttrs (_: { doCheck = false; })` changes
the derivation hash, so valkey (and everything depending on it, e.g. immich's
redis) can never be substituted from cache.nixos.org and must compile locally
on every bump — which is also why the flaky test suite was hit at all.
Dropping the overlay should allow pulling Hydra's pre-built, pre-tested
binaries. If a genuinely uncached rev comes up, prefer scoping the overlay to
immich only rather than all 14 hosts.

---

## Performance / efficiency

### 11. Six separate `import nixpkgs-unstable { … }` evaluations in flake.nix
Each `specialArgs`/`extraSpecialArgs` site instantiates a fresh nixpkgs, which
is the single biggest eval-time and memory cost in this flake. Hoist one
instance into the outer `let`:

```nix
pkgs-unstable = import nixpkgs-unstable { inherit system; config.allowUnfree = true; };
```

and reference it everywhere. Same object, evaluated once.

### 12. `deploy-all.sh` runs deploy-rs from GitHub
`nix run github:serokell/deploy-rs` fetches/evaluates an unpinned deploy-rs
distinct from the flake input (already installed on the desktops as
`deploy-rs-pkg`). Use `nix run "$FLAKE#deploy-rs"` via an `apps` output, or
just call the installed `deploy` binary — faster, and the version that
deployed is the version that was locked.

### 13. `cache-min-ttl = 3600` in unbound
`pihole-common.nix` — forcing a 1-hour minimum TTL serves stale records for
services that intentionally use short TTLs (CDNs, failover, own Cloudflare
changes). With `prefetch = true` already on, the latency win is marginal;
drop it to 0–300.

---

## Config management

### 14. Deduplicate flake.nix with helpers
~80 of its 200 lines are the same four-line `nixosSystem` block repeated. A
couple of helpers collapse it and make adding a host a one-liner:

```nix
mkLxc = name: extraModules: nixpkgs.lib.nixosSystem {
  inherit system;
  specialArgs = { inherit pkgs-unstable hostsLib; };
  modules = [ ./lxc/${name}.nix ] ++ extraModules;
};
```

Passing `hostsLib` through `specialArgs` also removes the
`let hostsLib = import ../hosts.nix { inherit lib; };` boilerplate repeated in
~10 modules.

### 15. Standardise the sops age-key bootstrap
Three schemes currently coexist: caddy/immich read
`/home/deploy/.config/sops/age/keys.txt`, uptime derives from the SSH host key
(`age.sshKeyPaths`), and gb-grid uses `/var/lib/sops-nix/key.txt`. The uptime
approach is the best one: the host key already exists, nothing to copy
out-of-band, and `ssh-keyscan` gives the recipient. Converging on it removes
two manual provisioning steps and one secret-distribution channel.

### 16. `common-lxc.nix` duplicates `modules/locale.nix`
Timezone/locale are set inline; just import the module.

### 17. No automated checks
`checks` are already generated from deploy-rs; a tiny GitHub Action (or even a
pre-push hook) running `nix flake check` would catch eval errors before deploy
night. Adding `statix` and `deadnix` would mechanically catch things like the
dead `pihole.service` reference style of issue.

---

## Hardware performance / efficiency

### Framework laptop

#### 18. powertop auto-tune can fight power-profiles-daemon and lag USB input
`powerManagement.powertop.enable` runs `powertop --auto-tune` at boot, which
enables USB autosuspend on *everything* — the classic symptom is a
Bluetooth/USB mouse or keyboard that stutters for half a second after idle.
It also re-applies settings that ppd then manages differently. If input lag
has never been noticed, fine; otherwise replace it with explicit udev rules
for just the devices worth autosuspending, and let ppd own the rest.

#### 19. Battery charge limit
The `framework_laptop` EC driver exposes `charge_control_end_threshold` via
standard sysfs. Capping at ~80 % roughly doubles battery cycle life for a
machine that lives on the dock:

```nix
systemd.services.battery-charge-threshold = {
  wantedBy = [ "multi-user.target" ];
  serviceConfig.Type = "oneshot";
  script = ''echo 80 > /sys/class/power_supply/BAT1/charge_control_end_threshold'';
};
```

#### 20. No compressed swap tier
There's a 64 GB swapfile on NVMe for hibernate but nothing in front of it, so
any memory pressure goes straight to disk. `zswap` is the right choice here
(unlike zram it's hibernate-compatible — it writes back through the
swapfile): add `"zswap.enabled=1" "zswap.compressor=zstd"
"zswap.zpool=zsmalloc"` to `boot.kernelParams`.

#### 21. Wi-Fi power save
The MT7925 supports runtime power management but NetworkManager doesn't
enable it by default: `networking.networkmanager.wifi.powersave = true;`.
Worth ~0.3–0.5 W idle. (Revert if latency spikes appear on home Wi-Fi.)

#### 22. Panel power via ABM
`amdgpu.abmlevel=1` (up to 3) in kernelParams enables Adaptive Backlight
Management — one of the biggest single battery wins on AMD laptops (~1 W+ at
typical brightness), at the cost of slight color shift on battery. Level 1 is
barely perceptible.

### Desktop

#### 23. 64 GB swapfile with no hibernate wiring — pick one
`desktop-disko.nix` allocates the same 64 GB swapfile as the framework, but
`chris-desktop.nix` has no `boot.resumeDevice` / `resume_offset`, so it can
never hibernate — 64 GB of NVMe doing almost nothing. Either wire up
hibernation like the framework, or shrink it to ~8 GB and add
`zramSwap.enable = true;` (no hibernate constraint on the desktop, so zram is
the better fit there).

#### 24. Suspend-when-idle + Wake-on-LAN
The desktop runs 24/7-ish as a Sunshine host and Immich ML backend, but both
tolerate wake-on-demand: Moonlight can send a WoL packet, and Immich just
retries the ML endpoint. Enabling WoL on the NIC
(`networking.interfaces.<nic>.wakeOnLan.enable = true;`) plus auto-suspend
after idle would save 30–60 W around the clock — the largest energy win
available in this whole config. The hard part (taming spurious wake sources
via `disable-wake-sources`) is already done.

### LXC / Proxmox

#### 25. GPU transcode userspace drivers are missing in the containers
plex, transcode, and immich all do video work, and the immich comment says
"ffmpeg-full for QSV" — but none of these containers set
`hardware.graphics.enable` or install the Intel userspace stack, and
QSV/VAAPI needs both the passed-through `/dev/dri` *and* the drivers inside
the container:

```nix
hardware.graphics = {
  enable = true;
  extraPackages = with pkgs; [ intel-media-driver vpl-gpu-rt ];
};
```

Run `vainfo` inside each container to verify; if it errors, Plex and Immich
are silently software-transcoding right now — the difference between ~5 W and
a pegged CPU core per stream. Also check Immich's `ffmpeg.accel` setting in
`immich-config.json` and `services.plex.accelerationDevices` — defaults are
software.

#### 26. Unbound cache sizing vs container RAM
`msg-cache-size = 128m` + `rrset-cache-size = 256m` (`pihole-common.nix`) —
unbound's real footprint runs ~2× configured cache, so that's pushing
~700 MB per pihole for a home LAN whose entire hot DNS set fits in 10–20 MB.
If those LXCs have 512 MB–1 GB allocated, this risks OOM rather than helping.
16m/32m is plenty; `num-threads = 2` should also match the container's actual
core count.

---

## Small ones

- `lxc/caddy.nix` adds plain `pkgs.caddy` to `systemPackages` while the
  service runs the plugin build — drop it or use
  `config.services.caddy.package`.
- Caddy ACME email is `cmj2405@gmail.com` while git uses `chris@mcneill.fyi`
  (intentional?).
- `framework-disko.nix`'s `resume_offset=533760` in kernelParams silently
  breaks hibernation if the swapfile is ever recreated — worth a comment next
  to the swapfile definition.
- common-lxc both sets `allowedTCPPorts = [ 22 ]` and
  `openssh.openFirewall = true` (redundant).
