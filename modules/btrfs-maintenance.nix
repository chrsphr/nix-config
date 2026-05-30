{ ... }:

# Periodic btrfs scrub + weekly fstrim + nix store hardlink dedup.
# `discard=async` mount option (set in disko) handles TRIM at free-time;
# the fstrim timer is a belt-and-braces weekly sweep that also covers
# /boot vfat which doesn't do async discard.
{
  services.btrfs.autoScrub = {
    enable = true;
    interval = "monthly";
    fileSystems = [ "/" ];
  };
  services.fstrim.enable = true;
  nix.settings.auto-optimise-store = true;
}
