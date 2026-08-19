{ config, pkgs, lib, ... }:

# Pi-hole 2 as a NixOS container on minihutch. Config lives in
# pihole-common.nix — except the adlists, which are state in
# /var/lib/pihole/gravity.db, NOT declarative; the update timer
# re-downloads and rebuilds gravity from them.
# why: docs/notes.md#container-one-offs

{
  imports = [
    ./common.nix
    ./pihole-common.nix
  ];

  networking.hostName = "pihole-2";
}
