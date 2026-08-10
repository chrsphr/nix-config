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
    # extraUpFlags only ever runs on first login (tailscaled-autoconnect
    # skips an already-authenticated node), so it can't be the source of
    # truth — a manual `tailscale up --advertise-exit-node` had already
    # clobbered the subnet route here. extraSetFlags reapplies on every
    # activation; keep the two lists identical.
    #
    # No --accept-routes: this node advertises its own LAN, and accepting
    # tailnet routes back would invite a loop.
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
