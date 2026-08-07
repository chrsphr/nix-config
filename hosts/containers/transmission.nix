{ config, pkgs, lib, ... }:

# Transmission as a NixOS container on hutch — replaces the Proxmox LXC
# (hosts/lxc/transmission.nix). The LXC NFS-mounted the Media share at
# /mnt/media; here it's a bind of the local ZFS dataset at the same internal
# path (see hosts/hutch.nix), so /var/lib/transmission carries over
# unchanged.

{
  imports = [
    ./common.nix
  ];

  networking = {
    hostName = "transmission";
    firewall.allowedTCPPorts = [ 9091 ];
  };

  services.transmission = {
    enable = true;
    openFirewall = true;
    settings = {
      download-dir = "/mnt/media/Downloads";
      incomplete-dir = "/mnt/media/Downloads/.incomplete";
      incomplete-dir-enabled = true;
      rpc-bind-address = "0.0.0.0";
      rpc-whitelist-enabled = false;
      rpc-host-whitelist-enabled = false;
    };
  };

  # Allow transmission to write to the media bind mount
  users.users.transmission.extraGroups = [ "media" ];
}
