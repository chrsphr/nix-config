{ config, pkgs, lib, ... }:

let
  hostsLib = import ./hosts.nix { inherit lib; };
in
{
  imports = [
    ./common.nix
    ./modules/cloudflare-tunnel.nix
  ];

  networking = hostsLib.mkStaticNetwork "uptime" // {
    hostName = "uptime";
    firewall.allowedTCPPorts = [ 3001 ];
  };

  sops = {
    defaultSopsFile = ./secrets/uptime.yaml;
    age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
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
