{ config, pkgs, sops-nix, lib, ... }:

# Gatus uptime monitoring as a NixOS container on hutch — replaces the
# Proxmox LXC (hosts/lxc/uptime.nix). Same secrets/uptime.yaml; the LXC
# decrypts it with its SSH host key, so copy that key from the LXC into
# /var/lib/sops-nix/uptime/ on the host (bind-mounted to /var/secrets) before
# cutover. See docs/lxc-migration.md.

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
    # Originally the LXC's SSH host key (/etc/ssh/ssh_host_ed25519_key) — but
    # that LXC died with the retired Proxmox node and the key was lost.
    # uptime.yaml is also encrypted to the *laptop key (recipient age132q904…),
    # so a copy of THAT key is used here instead (see .sops.yaml). Tradeoff:
    # the laptop master key now lives on hutch too — a compromise of this box
    # decrypts every sops secret. Acceptable for the homelab; replace with a
    # dedicated uptime key + re-encrypt if that ever stops being OK.
    age.keyFile = "/var/secrets/keys.txt";
    secrets.cloudflare_tunnel_token = {};
    secrets.proxmox_api_token = {};
    templates."gatus.env".content = ''
      PROXMOX_API_TOKEN=${config.sops.placeholder.proxmox_api_token}
    '';
  };

  services.gatus = {
    enable = true;
    environmentFile = config.sops.templates."gatus.env".path;
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
