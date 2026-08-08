{ config, pkgs, sops-nix, lib, ... }:

# Gatus uptime monitoring as a NixOS container on hutch. Decrypts
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
    # The original per-host key (this container's predecessor's SSH host key)
    # was lost with the hardware it lived on. uptime.yaml is also encrypted to
    # the *laptop key (recipient age132q904…), so a copy of THAT key is used
    # here instead (see .sops.yaml). Tradeoff: the laptop master key lives on
    # hutch too — a compromise of this box decrypts every sops secret.
    # Acceptable for the homelab; replace with a dedicated uptime key +
    # re-encrypt if that ever stops being OK.
    age.keyFile = "/var/secrets/keys.txt";
    # Persistent path: /run/secrets is tmpfs and containers don't re-run
    # activation at boot, so the default path would vanish on every reboot.
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
