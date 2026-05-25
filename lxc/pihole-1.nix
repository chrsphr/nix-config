{ config, pkgs, lib, ... }:

let
  hostsLib = import ../hosts.nix { inherit lib; };
in
{
  imports = [
    ./common-lxc.nix
    ./pihole-common.nix
  ];

  networking = hostsLib.mkStaticNetwork "pihole-1" // {
    hostName = "pihole-1";
  };
}
