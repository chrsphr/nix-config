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

}