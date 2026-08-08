{ config, pkgs, sops-nix, lib, ... }:

# Caddy reverse proxy as a NixOS container on hutch — replaces the Proxmox
# LXC (hosts/lxc/caddy.nix). Same secrets/caddy.yaml; the age key is copied
# from the LXC into /var/lib/sops-nix/caddy/ on the host (bind-mounted to
# /var/secrets) before cutover. See docs/lxc-migration.md.

let
  hostsLib = import ../../lib/network.nix { inherit lib; };
in
{
  imports = [
    ./common.nix
    sops-nix.nixosModules.sops
  ];

  networking = {
    hostName = "caddy";
    firewall.allowedTCPPorts = [ 80 443 ];
  };

  sops = {
    defaultSopsFile = ../../secrets/caddy.yaml;
    # Same age key the LXC keeps at /home/deploy/.config/sops/age/keys.txt.
    age.keyFile = "/var/secrets/keys.txt";
    secrets = {
      cloudflare_api_token = {
        owner = "caddy";
        # Not the default /run/secrets (tmpfs): containers don't re-run their
        # activation at boot, so files under /run are wiped on every reboot
        # and never recreated until the next host deploy. /var lives on the
        # container's persistent btrfs subvolume.
        path = "/var/lib/sops/cloudflare_api_token";
      };
    };
  };

  # Caddy reverse proxy with Cloudflare DNS plugin
  services.caddy = {
    enable = true;
    package = pkgs.caddy.withPlugins {
      plugins = [ "github.com/caddy-dns/cloudflare@v0.2.2" ];
      hash = "sha256-mqIa0wI/VfjDblg0NnkzKllWHXZZPLwHP8xEVSwZuPE=";
    };
    email = "cmj2405@gmail.com";

    globalConfig = ''
      acme_dns cloudflare {env.CLOUDFLARE_API_TOKEN}
    '';

    extraConfig = ''
      *.${hostsLib.domain} {
        tls {
          dns cloudflare {env.CLOUDFLARE_API_TOKEN}
        }

${hostsLib.generateCaddyConfig}
      }
    '';
  };

  # Set Cloudflare API token as environment variable for Caddy
  systemd.services.caddy.serviceConfig = {
    EnvironmentFile = config.sops.secrets.cloudflare_api_token.path;
  };
}
