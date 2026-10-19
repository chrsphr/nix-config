{ config, pkgs, lib, ... }:

# Radarr as a NixOS container on hutch. The Media dataset is bind mounted at
# /mnt/media (see hosts/hutch.nix). Movies only — Sonarr handles TV.

{
  imports = [
    ./common.nix
  ];

  networking.hostName = "radarr";

  services.radarr = {
    enable = true;
    openFirewall = true;
  };

  # Allow radarr to access the media bind mount
  users.users.radarr.extraGroups = [ "media" ];
}
