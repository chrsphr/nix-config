{ config, pkgs, lib, ... }:

{
  imports = [
    ./common.nix
    ./pihole-common.nix
  ];


  networking.interfaces.eth0.ipv4.addresses = lib.mkForce [{
    address = "192.168.1.9";
    prefixLength = 24;
  }];
}