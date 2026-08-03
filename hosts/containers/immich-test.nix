{ config, pkgs, pkgs-unstable, lib, ... }:

{
  imports = [
    ./common.nix
  ];

  networking.firewall.allowedTCPPorts = [ 2283 ];

  services.immich = {
    enable = true;
    package = pkgs-unstable.immich;
    host = "0.0.0.0";
    port = 2283;

    # Local storage for the test container (no NFS media share).
    mediaLocation = "/var/lib/immich/media";

    database.enable = true;
    redis.enable = true;
  };
}
