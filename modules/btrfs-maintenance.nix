{ ... }:

# Periodic btrfs scrub + weekly fstrim + nix store hardlink dedup.
# `discard=async` mount option (set in disko) handles TRIM at free-time;
# the fstrim timer is a belt-and-braces weekly sweep that also covers
# /boot vfat which doesn't do async discard.
{
  services.btrfs.autoScrub = {
    enable = true;
    # Weekly, not monthly: the ConditionACPower below can skip an occurrence
    # outright (see caveat there), so a shorter interval bounds how long a
    # scrub can go missed. Scrub is read-only — no extra write wear.
    interval = "weekly";
    fileSystems = [ "/" ];
  };
  services.fstrim.enable = true;
  nix.settings.auto-optimise-store = true;

  # Don't burn battery on maintenance. A scrub is a full-device read (10+ min of
  # sustained NVMe + CPU on the laptop); fstrim is cheaper but equally pointless
  # to run unplugged. No-op on the desktop — systemd treats "no battery" as on AC.
  #
  # Caveat: a condition failure still counts as the timer having fired, so
  # Persistent=true does NOT re-run a skipped occurrence — it waits for the next
  # one. Hence the weekly scrub interval: missing one costs a week, not a month.
  # unitConfig, not serviceConfig — ConditionACPower is a [Unit] directive and
  # systemd silently ignores it if it lands in [Service].
  systemd.services."btrfs-scrub--".unitConfig.ConditionACPower = true;
  systemd.services.fstrim.unitConfig.ConditionACPower = true;
}
