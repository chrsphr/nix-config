{ config, pkgs, lib, ... }:

{
  imports = [
    ./common.nix
    ../lxc/pihole-common.nix
  ];
}
