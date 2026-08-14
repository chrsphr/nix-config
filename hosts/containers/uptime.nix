{ config, pkgs, sops-nix, lib, ... }:

# Gatus uptime monitoring as a NixOS container on minihutch. Decrypts
# secrets/uptime.yaml with the age key at /var/lib/sops-nix/uptime/keys.txt
# on the host, bind-mounted read-only to /var/secrets.

let
  hostsLib = import ../../lib/network.nix { inherit lib; };
in
{
  imports = [
    ./common.nix
    ../../modules/cloudflare-tunnel.nix
    sops-nix.nixosModules.sops
  ];

  networking = {
    hostName = "uptime";
    firewall.allowedTCPPorts = [ 3001 ];
  };

  sops = {
    defaultSopsFile = ../../secrets/uptime.yaml;
    # A copy of the laptop master key — accepted tradeoff.
    # why: docs/notes.md#secrets-under-var
    age.keyFile = "/var/secrets/keys.txt";
    # Persistent path, not /run/secrets. why: docs/notes.md#secrets-under-var
    secrets.cloudflare_tunnel_token.path = "/var/lib/sops/cloudflare_tunnel_token";
  };

  services.gatus = {
    enable = true;
    settings = {
      web.port = 3001;

      storage = {
        type = "sqlite";
        path = "/var/lib/gatus/data.db";
      };

      endpoints = hostsLib.generateGatusEndpoints {
        extra = [
          {
            name = "Internet Access";
            group = "Hutch Primary Services";
            url = "tcp://1.1.1.1:53";
            interval = "60s";
            conditions = [ "[CONNECTED] == true" ];
          }
        ];
      };
    };
  };

  services.cloudflare-tunnel = {
    enable = true;
    tokenFile = config.sops.secrets.cloudflare_tunnel_token.path;
  };
}
