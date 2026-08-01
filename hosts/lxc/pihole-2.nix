{ config, pkgs, lib, ... }:

let
  hostsLib = import ../../lib/network.nix { inherit lib; };
in
{
  imports = [
    ./common-lxc.nix
    ./pihole-common.nix
  ];

  networking = hostsLib.mkStaticNetwork "pihole-2" // {
    hostName = "pihole-2";
  };
}
