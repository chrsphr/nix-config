{ config, pkgs, pkgs-unstable, lib, ... }:

{
  imports = [
    ./common-lxc.nix
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

# QSV userspace stack for hardware transcode. /dev/dri comes from the dev0/dev1
# entries in the Proxmox config (204.conf) — their gid= must match this
# container's video (26) / render (303) groups.
hardware.graphics = {
  enable = true;
  extraPackages = with pkgs; [ intel-media-driver vpl-gpu-rt ];
};
environment.systemPackages = [ pkgs.libva-utils ];  # `vainfo` to verify QSV

}