{ config, pkgs, lib, ... }:

# Sonarr + Prowlarr (co-located, as on the LXC) as a NixOS container on
# hutch — replaces the Proxmox LXC (hosts/lxc/sonarr.nix). The LXC
# NFS-mounted the whole Media share at /mnt/media; here it's a bind of the
# local ZFS dataset at the same internal path (see hosts/hutch.nix), so
# /var/lib/sonarr and /var/lib/prowlarr carry over unchanged.

{
  imports = [
    ./common.nix
  ];

  networking.hostName = "sonarr";

  services.sonarr = {
    enable = true;
    openFirewall = true;
  };

  services.prowlarr = {
    enable = true;
    openFirewall = true;
  };

  # Allow sonarr to access the media bind mount
  users.users.sonarr.extraGroups = [ "media" ];
}
