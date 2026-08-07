{ config, pkgs, pkgs-unstable, sops-nix, lib, ... }:

# Production immich as a NixOS container on hutch — replaces the Proxmox
# LXC (hosts/lxc/immich.nix). Media comes from the local ZFS pool via a bind
# mount (hostPath /mnt/Hutch/Media/Photos, see hosts/hutch.nix) instead
# of the NFS share the Proxmox host mounted into the LXC. Internal paths are
# identical to the LXC (/mnt/media/Photos), so the library and database carry
# over unchanged.

{
  imports = [
    ./common.nix
    ../../modules/cloudflare-tunnel.nix
    sops-nix.nixosModules.sops
  ];

  networking.hostName = "immich";

  # Same secrets file and age key as the LXC — the key is bind-mounted from
  # the hutch host (/var/lib/sops-nix/immich) at container start.
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
          baseConfig = builtins.fromJSON (builtins.readFile ../lxc/immich-config.json);
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

    # Same path the LXC used — now a bind mount of the local ZFS dataset
    # rather than the NFS share.
    mediaLocation = "/mnt/media/Photos";

    # Load the JSON configuration from sops template (includes injected secrets)
    environment.IMMICH_CONFIG_FILE = config.sops.templates."immich-config.json".path;

    database.enable = true;
    redis.enable = true;

    # Default is [] which sets PrivateDevices and blocks all device access —
    # QSV needs the render node visible inside the unit's sandbox.
    accelerationDevices = [ "/dev/dri/renderD128" ];
  };

  # QSV userspace stack. Requires /dev/dri inside the container — on baremetal
  # that's just a bind mount + allowedDevices if hutch's CPU has an Intel iGPU
  # (commented-out snippet in hosts/hutch.nix). Until then hardware
  # transcoding is unavailable and immich falls back to CPU.
  hardware.graphics = {
    enable = true;
    extraPackages = with pkgs; [ intel-media-driver vpl-gpu-rt ];
  };
  users.users.immich.extraGroups = [ "video" "render" ];
  environment.systemPackages = [ pkgs.libva-utils ];  # `vainfo` to verify QSV

  # The LXC wrote to the library over NFS with mapall chrsphr:root, so every
  # existing file is uid 3000. Match that here (nspawn shares the host's uid
  # space) so ownership stays consistent with desktop/framework NFS access.
  users.users.immich.uid = 3000;

  # The LXC guarded immich-server with ConditionPathIsMountPoint because its
  # media mount was optional. Here the equivalent guard is on the host:
  # container@immich won't start unless /mnt/Hutch/Media is mounted
  # (see hosts/hutch.nix).

  services.cloudflare-tunnel = {
    enable = true;
    tokenFile = config.sops.secrets.cloudflare_tunnel_token.path;
  };

  networking.firewall.allowedTCPPorts = [ 2283 ];
}
