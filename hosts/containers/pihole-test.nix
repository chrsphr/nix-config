{ config, pkgs, lib, ... }:

{
  imports = [
    ./common.nix
    ./pihole-common.nix
  ];
}
