{ config, pkgs, pkgs-unstable, sops-nix, lib, ... }:

# Immich as a NixOS container on hutch. The photo library is a bind mount of
# the local ZFS dataset (hosts/hutch.nix), exposed at /mnt/media/Photos.

{
  imports = [
    ./common.nix
    ../../modules/cloudflare-tunnel.nix
    sops-nix.nixosModules.sops
  ];

  networking.hostName = "immich";

  # Age key bind-mounted from the host (/var/lib/sops-nix/immich).
  sops = {
    defaultSopsFile = ../../secrets/immich.yaml;
    age.keyFile = "/var/secrets/age-keys.txt";
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

    mediaLocation = "/mnt/media/Photos";

    # Load the JSON configuration from sops template (includes injected secrets)
    environment.IMMICH_CONFIG_FILE = config.sops.templates."immich-config.json".path;

    database.enable = true;
    redis.enable = true;

    # Default [] sets PrivateDevices; QSV needs the render node visible.
    # why: docs/notes.md#container-one-offs
    accelerationDevices = [ "/dev/dri/renderD128" ];
  };

  # QSV userspace stack; /dev/dri arrives via bind mount + allowedDevices
  # from hosts/hutch.nix. why: docs/notes.md#hutch
  hardware.graphics = {
    enable = true;
    extraPackages = with pkgs; [ intel-media-driver vpl-gpu-rt ];
  };
  users.users.immich.extraGroups = [ "video" "render" ];
  environment.systemPackages = [ pkgs.libva-utils ];  # `vainfo` to verify QSV

  # Existing library files are uid 3000. why: docs/notes.md#container-one-offs
  users.users.immich.uid = 3000;

  services.cloudflare-tunnel = {
    enable = true;
    tokenFile = config.sops.secrets.cloudflare_tunnel_token.path;
  };

  networking.firewall.allowedTCPPorts = [ 2283 ];
}
