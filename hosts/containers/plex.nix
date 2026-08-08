{ config, pkgs, pkgs-unstable, lib, ... }:

# Plex as a NixOS container on hutch. The library arrives as read-only binds
# of the local ZFS datasets at /media/{Movies,Music,TV} (see hosts/hutch.nix).

{
  imports = [
    ./common.nix
  ];

  networking.hostName = "plex";

  services.plex = {
    enable = true;
    openFirewall = true;
    user = "plex";
    group = "plex";
    package = pkgs-unstable.plex;
  };

  users.users.plex.extraGroups = [ "video" "render" ];

  # QSV userspace stack for hardware transcode. Needs /dev/dri inside the
  # container — on baremetal that's just a bind mount + allowedDevices if
  # hutch's CPU has an Intel iGPU (commented-out snippet in hosts/hutch.nix).
  # Until then Plex transcodes on CPU.
  hardware.graphics = {
    enable = true;
    extraPackages = with pkgs; [ intel-media-driver vpl-gpu-rt ];
  };
  environment.systemPackages = [ pkgs.libva-utils ];  # `vainfo` to verify QSV
}
