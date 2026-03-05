{ config, pkgs, lib, ... }:

let
  hostsLib = import ./hosts.nix { inherit lib; };
in
{
  imports = [
    ./common.nix
    ./pihole-common.nix
  ];

  networking = hostsLib.mkStaticNetwork "pihole-2" // {
    hostName = "pihole-2";
  };
}
