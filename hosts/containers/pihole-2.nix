{ config, pkgs, lib, ... }:

# Pi-hole 2 as a NixOS container on hutch — replaces the Proxmox LXC
# (hosts/lxc/pihole-2.nix). Config is fully declarative (pihole-common.nix);
# gravity regenerates itself via the update timer.

{
  imports = [
    ./common.nix
    ./pihole-common.nix
  ];

  networking.hostName = "pihole-2";
}
