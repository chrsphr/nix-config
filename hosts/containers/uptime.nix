{ config, pkgs, lib, network, ... }:

# Gatus uptime monitoring as a NixOS container on minihutch. Decrypts
# secrets/uptime.yaml with the age key at /var/lib/sops-nix/uptime/keys.txt
# on the host, bind-mounted read-only to /var/secrets.

{
  imports = [
    ../../modules/cloudflare-tunnel.nix
  ];

  networking.firewall.allowedTCPPorts = [ 3001 ];

  sops = {
    # Decrypted with a copy of the laptop master key — accepted tradeoff.
    # why: docs/notes.md#secrets-under-var

    # Persistent path, not /run/secrets. why: docs/notes.md#secrets-under-var
    secrets.cloudflare_tunnel_token.path = "/var/lib/sops/cloudflare_tunnel_token";
  };

  services.gatus = {
    enable = true;
    settings = {
      web.port = 3001;
      metrics = true;

      storage = {
        type = "sqlite";
        path = "/var/lib/gatus/data.db";
      };

      endpoints = network.generateGatusEndpoints {
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
