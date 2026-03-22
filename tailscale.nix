{ config, pkgs, lib, ... }:

let
  hostsLib = import ./hosts.nix { inherit lib; };
in
{
  imports = [
    ./common.nix
  ];

  networking = hostsLib.mkStaticNetwork "tailscale" // {
    hostName = "tailscale";
    firewall = {
      trustedInterfaces = [ "tailscale0" ];
      checkReversePath = "loose";
      allowedTCPPorts = [ 8080 ];
    };
  };

  # Enable IP forwarding for exit node
  boot.kernel.sysctl = {
    "net.ipv4.ip_forward" = 1;
    "net.ipv6.conf.all.forwarding" = 1;
  };

  # Tailscale
  services.tailscale = {
    enable = true;
    openFirewall = true;
    useRoutingFeatures = "server";
    extraUpFlags = [
      "--advertise-routes=192.168.1.0/24"
      "--accept-routes"
    ];
  };

  # Health check endpoint for monitoring
  services.nginx = {
    enable = true;
    virtualHosts."health" = {
      listen = [{ addr = "0.0.0.0"; port = 8080; }];
      locations."/health".return = "200 'ok'";
    };
  };
}
