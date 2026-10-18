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
    # 9180: Caddy metrics for prometheus (see the :9180 block below).
    firewall.allowedTCPPorts = [ 80 443 9180 ];
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
      hash = "sha256-UPd4CWjm8Cq5EZ9OkBCglE23hD8+przFBSw8Ey6zMz8=";
    };
    email = "cmj2405@gmail.com";

    # Turns metrics collection on for the :9180 endpoint below.
    globalConfig = ''
      metrics
    '';

    extraConfig = ''
      # Metrics on plain HTTP for prometheus. Not the admin API: that has no
      # auth and must stay on localhost.
      :9180 {
        metrics
      }

      *.${hostsLib.domain} {
        tls {
          dns cloudflare {env.CLOUDFLARE_API_TOKEN}
        }

        # Access logs go to the journal. Query strings and token-bearing headers
        # are stripped: Plex, Sonarr and Pi-hole put API keys in them.
        log {
          output stdout
          format filter {
            request>uri regexp `\?.*` `?REDACTED`
            request>headers>Referer delete
            request>headers>X-Plex-Token delete
            request>headers>X-Api-Key delete
            request>headers>X-Ftl-Sid delete
          }
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
