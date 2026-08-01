{ config, pkgs, lib, ... }:

let
  hostsLib = import ../../lib/network.nix { inherit lib; };
in
{
  imports = [
    ./common-lxc.nix
  ];

  networking = hostsLib.mkStaticNetwork "transmission" // {
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

  # Allow transmission to write to media mount
  users.users.transmission.extraGroups = [ "media" ];
}
