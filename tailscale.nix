{ config, pkgs, lib, ... }:

{
  imports = [
    ./common.nix
  ];

  networking.hostName = "tailscale";

  # Static IP
  networking.interfaces.eth0.ipv4.addresses = lib.mkForce [{
    address = "192.168.1.207";
    prefixLength = 24;
  }];
  networking.defaultGateway = {
    address = "192.168.1.1";
    interface = "eth0";
  };
  networking.nameservers = [ "192.168.1.9" "192.168.1.10" ];

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
  };

  # Open firewall for forwarded traffic
  networking.firewall = {
    trustedInterfaces = [ "tailscale0" ];
    checkReversePath = "loose";
    allowedTCPPorts = [ 8080 ];
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
