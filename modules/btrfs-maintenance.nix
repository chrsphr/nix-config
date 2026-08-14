{ ... }:

# Periodic btrfs scrub + weekly fstrim + nix store hardlink dedup.
# why: docs/notes.md#btrfs-maintenance
{
  services.btrfs.autoScrub = {
    enable = true;
    interval = "weekly";  # not monthly: AC-condition skips aren't re-run
    fileSystems = [ "/" ];
  };
  services.fstrim.enable = true;
  nix.settings.auto-optimise-store = true;

  # Don't burn battery on maintenance. Must be unitConfig, not serviceConfig.
  systemd.services."btrfs-scrub--".unitConfig.ConditionACPower = true;
  systemd.services.fstrim.unitConfig.ConditionACPower = true;
}
