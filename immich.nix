{ config, pkgs, pkgs-unstable, lib, ... }:

{
  imports = [
    ./common.nix
  ];

  ### Networking (adjust IP as needed)
  networking = {
    hostName = "immich";
    #interfaces.eth0.ipv4.addresses = [{
    #  address = "192.168.1.9";
    #  prefixLength = 24;
    #}];
    #defaultGateway = {
    #address = "192.168.1.1";
    #interface = "eth0";
    #};
    #nameservers = [ "1.1.1.1" ];
  };

  # Configure sops for secrets management
  sops = {
    defaultSopsFile = ./secrets/immich.yaml;
    age.keyFile = "/home/deploy/.config/sops/age/keys.txt";
    secrets = {
      oauth_client_id = {
        owner = "immich";
      };
      oauth_client_secret = {
        owner = "immich";
      };
    };
    templates."immich-config.json" = {
      owner = "immich";
      content = builtins.toJSON (
        let
          baseConfig = builtins.fromJSON (builtins.readFile ./immich-config.json);
        in
          lib.recursiveUpdate baseConfig {
            oauth = {
              clientId = config.sops.placeholder.oauth_client_id;
              clientSecret = config.sops.placeholder.oauth_client_secret;
            };
          }
      );
    };
  };

  services.immich = {
    enable = true;
    package = pkgs-unstable.immich;
    host = "0.0.0.0";
    port = 2283;

    # Media storage location
    mediaLocation = "/mnt/media/Photos";

    # Load the JSON configuration from sops template (includes injected secrets)
    # We can't use settings directly because it would try to read runtime paths at build time
    # Instead, we'll use environment variable to point to the config file
    environment.IMMICH_CONFIG_FILE = config.sops.templates."immich-config.json".path;

    # Database and Redis are managed automatically by the Immich module
    database.enable = true;
    redis.enable = true;
  };

  environment.systemPackages = with pkgs; [
    ffmpeg-full  # Use full ffmpeg for QSV hardware acceleration support
    cloudflared
  ];

  # Cloudflare Tunnel
  systemd.services.cloudflared = {
    description = "Cloudflare Tunnel";
    after = [ "network.target" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      ExecStart = "${pkgs.cloudflared}/bin/cloudflared tunnel run --token eyJhIjoiNjkzMWUxYTc0NWIwMWViMDcwM2YxYTU0YWE4MjcxNzYiLCJ0IjoiYTEzODFiNGItYmMwZS00YWFlLTgxMTgtZDk1MTQwOTA1MWUxIiwicyI6Ik5HWXpOVFU1TWpFdFpEbGhPQzAwTW1RM0xUZzNOalF0WmpVMk1qazBNREV3TTJabCJ9";
      Restart = "always";
      RestartSec = "5s";
    };
  };

  networking.firewall.allowedTCPPorts = [ 2283 ];
}