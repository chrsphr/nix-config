{ config, pkgs, lib, ... }:

# Sonarr + Prowlarr, co-located in one NixOS container on hutch. The Media
# dataset is bind mounted at /mnt/media (see hosts/hutch.nix).

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
