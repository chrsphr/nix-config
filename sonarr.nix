{ config, pkgs, lib, ... }:

let
  hostsLib = import ./hosts.nix { inherit lib; };
in
{
  imports = [
    ./common.nix
  ];

  networking = hostsLib.mkStaticNetwork "sonarr" // {
    hostName = "sonarr";
  };

  services.sonarr = {
    enable = true;
    openFirewall = true;
  };

  # Allow sonarr to access media mount
  users.users.sonarr.extraGroups = [ "media" ];
}
