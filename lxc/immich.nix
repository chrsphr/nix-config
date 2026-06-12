{ config, pkgs, pkgs-unstable, lib, ... }:

{
  imports = [
    ./common-lxc.nix
    ../modules/cloudflare-tunnel.nix
  ];

  networking.hostName = "immich";

  # Configure sops for secrets management
  sops = {
    defaultSopsFile = ../secrets/immich.yaml;
    age.keyFile = "/home/deploy/.config/sops/age/keys.txt";
    secrets = {
      oauth_client_id = {
        owner = "immich";
      };
      oauth_client_secret = {
        owner = "immich";
      };
      cloudflare_tunnel_token = {};
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

  # The photo library lives on the Media NFS share, bind-mounted from the Proxmox
  # host as an *optional* mount (lxc.mount.entry … bind,optional in 203.conf) so
  # the container still boots if the NFS share is unavailable. Guard the server so
  # it won't run library-less when the mount is absent — it stays down until
  # /mnt/media/Photos is actually mounted again.
  systemd.services.immich-server.unitConfig.ConditionPathIsMountPoint = "/mnt/media/Photos";

  environment.systemPackages = with pkgs; [
    ffmpeg-full  # Use full ffmpeg for QSV hardware acceleration support
  ];

  services.cloudflare-tunnel = {
    enable = true;
    tokenFile = config.sops.secrets.cloudflare_tunnel_token.path;
  };

  networking.firewall.allowedTCPPorts = [ 2283 ];
}