{ config, pkgs, sops-nix, lib, ... }:

# Caddy reverse proxy as a NixOS container on minihutch. Decrypts
# secrets/caddy.yaml with the age key at /var/lib/sops-nix/caddy/keys.txt on
# the host, bind-mounted read-only to /var/secrets.

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
    age.keyFile = "/var/secrets/keys.txt";
    secrets = {
      cloudflare_api_token = {
        owner = "caddy";
        # Persistent path, not /run/secrets. why: docs/notes.md#secrets-under-var
        path = "/var/lib/sops/cloudflare_api_token";
      };
    };
  };

  # Caddy reverse proxy with Cloudflare DNS plugin
  services.caddy = {
    enable = true;
    package = pkgs.caddy.withPlugins {
      plugins = [ "github.com/caddy-dns/cloudflare@v0.2.2" ];
      hash = "sha256-EKFsWWPds2ESNUXzW1dgRhV8OXjGkweewHYEhEX7Aio=";
    };
    email = "cmj2405@gmail.com";

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
