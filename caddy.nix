{ config, pkgs, lib, ... }:

{
  imports = [
    ./common.nix
  ];

  ### Networking
  networking = {
    hostName = "caddy";
    firewall.allowedTCPPorts = [ 80 443 ];
  };

  # Configure sops for secrets management
  sops = {
    defaultSopsFile = ./secrets/caddy.yaml;
    age.keyFile = "/home/deploy/.config/sops/age/keys.txt";
    secrets = {
      cloudflare_api_token = {
        owner = "caddy";
      };
    };
  };

  # Caddy reverse proxy with Cloudflare DNS plugin
  services.caddy = {
    enable = true;
    package = pkgs.caddy.withPlugins {
      plugins = [ "github.com/caddy-dns/cloudflare@v0.2.2" ];
      hash = "sha256-SrAHzXhaT3XO3jypulUvlVHq8oiLVYmH3ibh3W3aXAs=";
    };
    email = "cmj2405@gmail.com";

    globalConfig = ''
      acme_dns cloudflare {env.CLOUDFLARE_API_TOKEN}
    '';

    extraConfig = ''
      *.mcneill.fyi {
        tls {
          dns cloudflare {env.CLOUDFLARE_API_TOKEN}
        }

        @ha host ha.mcneill.fyi
        handle @ha {
          reverse_proxy 192.168.1.11:8123 {
            header_up X-Forwarded-For {remote_host}
            header_up X-Forwarded-Proto {scheme}
            header_up X-Forwarded-Host {host}
          }
        }

        @grafana host grafana.mcneill.fyi
        handle @grafana {
          reverse_proxy 192.168.1.61:3000
        }

        @immich host immich.mcneill.fyi
        handle @immich {
          reverse_proxy 192.168.1.127:2283
        }

        @lilnas host lilnas.mcneill.fyi
        handle @lilnas {
          reverse_proxy https://192.168.1.12:443 {
            transport http {
              tls_insecure_skip_verify
            }
          }
        }

        @sonarr host sonarr.mcneill.fyi
        handle @sonarr {
          reverse_proxy 192.168.9.3:8989
        }

        @transmission host transmission.mcneill.fyi
        handle @transmission {
          reverse_proxy 192.168.9.2:9091
        }

        @pihole1 host pihole-1.mcneill.fyi
        handle @pihole1 {
          reverse_proxy 192.168.1.9:80
        }

        @pihole2 host pihole-2.mcneill.fyi
        handle @pihole2 {
          reverse_proxy 192.168.1.10:80
        }
      }
    '';
  };

  # Set Cloudflare API token as environment variable for Caddy
  systemd.services.caddy.serviceConfig = {
    EnvironmentFile = config.sops.secrets.cloudflare_api_token.path;
  };

  environment.systemPackages = with pkgs; [
    caddy
  ];
}
