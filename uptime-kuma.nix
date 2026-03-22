{ config, pkgs, pkgs-unstable, lib, ... }:

let
  hostsLib = import ./hosts.nix { inherit lib; };
in
{
  imports = [
    ./common.nix
    ./modules/cloudflare-tunnel.nix
  ];

  networking = hostsLib.mkStaticNetwork "uptime-kuma" // {
    hostName = "uptime-kuma";
    firewall.allowedTCPPorts = [ 3001 ];
  };

  # Configure sops for secrets management
  sops = {
    defaultSopsFile = ./secrets/uptime-kuma.yaml;
    age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
    secrets.cloudflare_tunnel_token = {};
  };

  services.uptime-kuma = {
    enable = true;
    package = pkgs-unstable.uptime-kuma;
    settings = {
      PORT = "3001";
      HOST = "0.0.0.0";
    };
  };

  # Allow uptime-kuma to use ping (requires CAP_NET_RAW)
  systemd.services.uptime-kuma.serviceConfig.AmbientCapabilities = [ "CAP_NET_RAW" ];

  services.cloudflare-tunnel = {
    enable = true;
    tokenFile = config.sops.secrets.cloudflare_tunnel_token.path;
  };
}
