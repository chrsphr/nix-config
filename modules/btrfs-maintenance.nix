{ utils, ... }:

# Periodic btrfs scrub + weekly fstrim + nix store hardlink dedup.
# `discard=async` mount option (set in disko) handles TRIM at free-time;
# the fstrim timer is a belt-and-braces weekly sweep that also covers
# /boot vfat which doesn't do async discard.
let
  # systemd's ConditionACPower is true when any AC connector reads "online",
  # and also true on machines that have no AC connector at all — so this is a
  # no-op on the desktop and only defers work on the laptop.
  onACOnly = { unitConfig.ConditionACPower = true; };
in
{
  services.btrfs.autoScrub = {
    enable = true;
    interval = "monthly";
    fileSystems = [ "/" ];
  };
  services.fstrim.enable = true;

  # Periodic store optimisation rather than `nix.settings.auto-optimise-store`.
  # auto-optimise-store makes the daemon hash and hardlink every path as it is
  # added, so it taxes every build and every substitution; the timer does the
  # same dedup in one batch, off the critical path (and, below, off battery).
  nix.optimise.automatic = true;
  nix.optimise.dates = [ "weekly" ];

  # Keep the heavy periodic jobs off the battery. A full-disk scrub, a GC pass
  # and a store optimise are all long, IO-bound and CPU-bound — exactly the
  # work you don't want kicking off while unplugged. Trade-off: a run whose
  # timer elapses on battery is skipped rather than deferred, so a monthly
  # scrub can slip a month. `systemctl list-timers` shows the next elapse;
  # force one while docked with `systemctl start btrfs-scrub--.service`.
  systemd.services = {
    "btrfs-scrub-${utils.escapeSystemdPath "/"}" = onACOnly;
    fstrim = onACOnly;
    nix-gc = onACOnly;
    nix-optimise = onACOnly;
  };
}
