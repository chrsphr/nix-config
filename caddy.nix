{ config, pkgs, lib, ... }:

let
  hostsLib = import ./hosts.nix { inherit lib; };
in
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
      hash = "sha256-Gb1nC5fZfj7IodQmKmEPGygIHNYhKWV1L0JJiqnVtbs=";
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

  environment.systemPackages = with pkgs; [
    caddy
  ];
}
