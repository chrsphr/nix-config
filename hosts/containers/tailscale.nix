{ config, pkgs, lib, ... }:

# Tailscale exit node as a NixOS container on minihutch. The host grants
# /dev/net/tun and CAP_NET_ADMIN via containers.tailscale.enableTun
# (see hosts/minihutch.nix).

{
  imports = [
    ./common.nix
  ];

  networking = {
    hostName = "tailscale";
    firewall = {
      trustedInterfaces = [ "tailscale0" ];
      checkReversePath = "loose";
      allowedTCPPorts = [ 8080 ];
    };
  };

  # Enable IP forwarding for exit node. The container has its own network
  # namespace (privateNetwork), so these apply inside the container only.
  boot.kernel.sysctl = {
    "net.ipv4.ip_forward" = 1;
    "net.ipv6.conf.all.forwarding" = 1;
  };

  # Tailscale
  services.tailscale = {
    enable = true;
    openFirewall = true;
    useRoutingFeatures = "server";
    # Keep both lists identical; no --accept-routes (loop risk).
    # why: docs/notes.md#container-one-offs
    extraUpFlags = [
      "--advertise-exit-node"
      "--advertise-routes=192.168.1.0/24"
    ];
    extraSetFlags = [
      "--advertise-exit-node"
      "--advertise-routes=192.168.1.0/24"
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
