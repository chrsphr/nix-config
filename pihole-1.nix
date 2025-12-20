{ config, pkgs, lib, ... }:

{
  imports = [
    ./common.nix
    ./pihole-common.nix
  ];

  services.pihole-web.hostName = lib.mkForce "pihole-1.mcneill.fyi";

  networking.interfaces.eth0.ipv4.addresses = lib.mkForce [{
    address = "192.168.1.9";
    prefixLength = 24;
  }];
}