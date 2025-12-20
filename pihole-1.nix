{ ... }:

{
  imports = [
    (import ./pihole-common.nix { hostname = "pihole-1"; ip = "192.168.1.9"; })
  ];
}