# Power & efficiency review — July 2026

Follow-up to `docs/config-review-2026-06.md`, focused on the Framework laptop.

Most of the June hardware list has landed: zswap, Wi-Fi powersave, the 90 %
charge cap, PSR re-enabled, lazy RCU, `pcie_aspm.policy=powersupersave`,
`amd_prefcore`, U-APSD on the AX210, avahi off, ABM tried and correctly
reverted. The remaining wins are less about kernel knobs and more about **what
runs when nothing is happening** — resident daemons, radio duty cycle, and
periodic jobs that fire on battery.

Everything in "Applied" is in this branch. Everything in "Worth considering"
has a trade-off that's a judgement call, so it's written up with the diff
rather than applied.

---

## Applied

### 1. Periodic maintenance no longer runs on battery
`modules/btrfs-maintenance.nix`

A monthly btrfs scrub reads the entire SSD; `nix-gc` and `nix-optimise` are
long CPU+IO jobs. All three could previously fire while unplugged. They now
carry `ConditionACPower=true`.

`ConditionACPower` is also true on machines with *no* AC connector, so this is
a no-op on the desktop and only defers work on the laptop — the module stays
shared.

Trade-off: a condition-failed run is *skipped*, not deferred, and the timer's
bookkeeping still advances. A scrub whose monthly elapse lands on battery slips
to the next month. `systemctl list-timers` shows the next elapse; force one
while docked with `systemctl start btrfs-scrub--.service`.

### 2. `auto-optimise-store` → periodic `nix.optimise`
`modules/btrfs-maintenance.nix`

`nix.settings.auto-optimise-store` makes the daemon hash and hardlink every
path *as it is added* to the store, so it taxes every build and every
substitution — noticeable on large closure pulls after a `nix flake update`.
Replaced with `nix.optimise.automatic` on a weekly timer, which does the same
dedup in one batch, off the critical path and (per #1) off battery.

### 3. Bluetooth `FastConnectable` off on the laptop
`chris-framework.nix`

`common-desktop.nix` sets `FastConnectable = true` for both machines. BlueZ's
own `main.conf` documents this as increasing power consumption: it shortens the
page-scan interval so the adapter is listening for inbound connections far more
often while idle. Fine on a desktop, not on a battery. Overridden to `false`
here with `mkForce`; revert if reconnecting a headset or mouse after sleep
becomes noticeably slower.

### 4. `sshd` socket-activated on the laptop
`chris-framework.nix`

The laptop isn't in `hosts.nix`, so it's not a deploy-rs node — inbound SSH is
a convenience over Tailscale only. `services.openssh.startWhenNeeded = true`
drops the resident daemon; behaviour over Tailscale is unchanged.

### 5. Docker no longer resident
`chris-framework.nix`

`virtualisation.docker.enableOnBoot = false`. dockerd (plus containerd and its
shims) now starts on first touch of `/var/run/docker.sock` instead of at boot.
The stated use is the gb-grid `nix develop` shell bringing a compose stack up by
hand, which socket activation covers.

Caveat: containers created with `--restart=always` will no longer come back on
their own. Set `enableOnBoot = true` again if that's ever wanted.

### 6. `upower` critical-battery action no longer tries to hibernate
`chris-framework.nix`

This is the one that reads as a latent bug rather than a tuning knob. Hibernate
was deliberately disabled on 2026-07-12 (amdgpu TTM LRU corruption on resume,
16 crashes), but only via the logind handlers —
`services.upower.criticalPowerAction` still had its default of `HybridSleep`.
HybridSleep writes a hibernation image before suspending, so a battery that
runs flat resumes through the exact amdgpu path hibernate was disabled to
avoid. Set to `PowerOff`; at 2 % remaining the machine is going down anyway,
and the swapfile / `resume_offset` wiring stays in place for when hibernate can
be restored.

### 7. PSR override made order-independent
`chris-framework.nix`

`amdgpu.dcdebugmask=0x0` relied on landing after nixos-hardware's
`dcdebugmask=0x10` through incidental module evaluation order. Wrapped in
`lib.mkAfter`, which puts it at order priority 1500 and therefore after every
default-priority definition, guaranteed. No behavioural change if it was
already winning — verified last in `boot.kernelParams` by evaluation.

---

## Worth considering (not applied)

### 8. GNOME file indexing — the biggest remaining background consumer
`services.gnome.localsearch.enable` and `services.gnome.tinysparql.enable` are
both `mkDefault true` under the GNOME module. localsearch (ex tracker-miners)
crawls and full-text-indexes `$HOME`, and re-crawls on change — the classic
"why is my laptop warm doing nothing" culprit, and by some distance the largest
idle CPU/IO item left on this machine.

```nix
services.gnome.localsearch.enable = false;
services.gnome.tinysparql.enable = false;
```

Cost: no full-text search in Files, and the GNOME Shell search providers that
depend on it go quiet. If you actually use Shell search for documents, keep it.
Worth watching `btop` for a few minutes after a big `darktable` import or a
`nix flake update` before deciding.

### 9. `iio-sensor-proxy` is running for a sensor you've disabled
nixos-hardware's Framework 13 module sets `hardware.sensor.iio.enable = true`,
but `home/framework.nix` already turns GNOME's ambient auto-brightness off
(`ambient-enabled = false`) because it reacted choppily. That leaves the ALS
polling loop with no consumer.

Check first — the unit is D-Bus activated, so it may not actually be running:

```
systemctl status iio-sensor-proxy
```

If it is:

```nix
hardware.sensor.iio.enable = lib.mkForce false;
```

Also loses accelerometer auto-rotate, which the FW13 clamshell can't use.

### 10. `blur-my-shell`
`home/common-home.nix`. Continuous GPU blur passes on shell surfaces keep the
iGPU busier than a flat theme does, and it's most active exactly during
overview/workspace switching. Purely an aesthetics-vs-battery call, so it's
your shout — but it's a real cost, not a rounding error, and it's the only item
on this list you'd actually notice the absence of.

### 11. Deeper iwlwifi power save
On top of `networking.networkmanager.wifi.powersave = true`:

```nix
boot.extraModprobeConfig = ''
  options iwlmvm power_scheme=3   # 1=CAM, 2=balanced (default), 3=low power
'';
```

Marginal on top of what NetworkManager already negotiates, and reports on
whether it does anything on AX210-class parts are mixed — hence not applied.
Cheap to try, revert if latency gets spiky.

### 12. `vm.swappiness` with zswap
Default 60 was tuned for spinning rust. With zswap in front of the swapfile,
anonymous pages compress into RAM rather than hitting NVMe, so preferring them
over evicting page cache means *fewer* disk reads:

```nix
boot.kernel.sysctl."vm.swappiness" = 120;
```

Low impact in practice on a machine with this much RAM — it only matters under
real pressure.

### 13. GNOME idle/suspend timings are unmanaged
Nothing in `home/framework.nix` sets the power plugin's timeouts, so they're
whatever GNOME defaults to (and whatever initial-setup wrote). Worth pinning
explicitly:

```nix
dconf.settings = {
  "org/gnome/settings-daemon/plugins/power" = {
    sleep-inactive-battery-type = "suspend";
    sleep-inactive-battery-timeout = 600;   # 10 min on battery
    sleep-inactive-ac-type = "nothing";
    power-saver-profile-on-low-battery = true;
  };
  "org/gnome/desktop/session".idle-delay = lib.hm.gvariant.mkUint32 180;
};
```

(`idle-delay` is a `uint32` in the schema, hence `mkUint32`.)

### 14. `keyboard-backlight-timeout` — dead, and the design is a power sink
`services.keyboard-backlight-timeout.enable = false`, so 130 lines of
`modules/keyboard-backlight-timeout.nix` are inert. Note for whenever it gets
revived: the loop does `select(devices, [], [], 1.0)`, i.e. a 1 Hz wakeup of a
resident Python interpreter forever. That is itself the kind of idle-wakeup
cost avahi was disabled over — it would likely cost more than the backlight
saves. Block on `select` with a computed deadline instead of polling, or drop
the module entirely in favour of the EC's own backlight timeout
(`framework_tool`/`ectool`), which costs nothing on the host.

### 15. Cosmetic: options nixos-hardware already sets
`services.fprintd.enable`, `services.fwupd.enable` and
`services.power-profiles-daemon.enable` in `chris-framework.nix` are all
`mkDefault`-ed to the same values by `framework-amd-ai-300-series`. Harmless,
and arguably worth keeping as documentation of intent — flagging only so it
isn't mistaken for load-bearing config.

---

## Still open from the June review

### Desktop auto-suspend (June #24) — still the largest energy win in the repo
Wake-on-LAN landed (`networking.interfaces.eno1.wakeOnLan.enable`) and the
spurious-wake-source taming is done, but nothing suspends the desktop. It idles
24/7 as a Sunshine host and Immich ML backend, both of which tolerate
wake-on-demand. At 30–60 W around the clock this dwarfs every laptop item on
this page combined.

The blocker is that `services.sunshine.autoStart` holds a graphical session, so
GNOME's idle logic won't fire on its own. The usual shape:

```nix
# suspend after 30 min idle unless a Moonlight client is connected
systemd.targets.suspend-on-idle = { ... };
```

…is fiddly enough to deserve its own change rather than being smuggled into a
laptop branch. Sunshine exposes client state over its API, so the honest
version is a small timer that checks for active sessions before calling
`systemctl suspend`.

Everything else hardware-related from June (#18–#23, #25, #26) is either done
or explicitly rejected with a reason in the config comments.

---

## Measuring any of this

Nothing above is worth trusting without a before/after. On battery, idle,
screen on, lid open:

```sh
# instantaneous draw, µW — average a dozen samples
cat /sys/class/power_supply/BAT1/power_now

# where the wakeups are coming from
sudo powertop --time=60          # read only; do NOT --auto-tune

# per-core residency and package power
sudo turbostat --Summary --quiet --interval 10

# check the deep idle states are actually being reached
sudo cpupower idle-info
```

For #1 and #2 the win is "the fan doesn't spin up while unplugged", which
doesn't show in a 60-second average — check `systemctl list-timers` and
`journalctl -u btrfs-scrub--.service` instead.
