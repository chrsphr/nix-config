{ config, pkgs, lib, ... }:

# Network Optimizer for UniFi (security audit, SQM, speed tests, monitoring)
# as a NixOS container on hutch, built from source (pkgs/network-optimizer.nix).
# why: docs/notes.md#network-optimizer

let
  package = pkgs.callPackage ../../pkgs/network-optimizer.nix { };
  hostsLib = import ../../lib/network.nix { inherit lib; };
in
{
  imports = [
    ./common.nix
  ];

  networking = {
    hostName = "network-optimizer";
    # 8042: web UI. 5201: iperf3 server for client speed tests.
    # 8086: InfluxDB API/UI (one-time onboarding + optional Grafana access).
    firewall.allowedTCPPorts = [ 8042 5201 8086 ];
  };

  # Time-series store for Monitoring; one-time UI onboarding.
  # why: docs/notes.md#network-optimizer
  services.influxdb2.enable = true;

  users.users.network-optimizer = {
    isSystemUser = true;
    group = "network-optimizer";
  };
  users.groups.network-optimizer = { };

  # All state lives in /app/data (DOTNET_RUNNING_IN_CONTAINER semantics).
  # why: docs/notes.md#network-optimizer
  systemd.tmpfiles.rules = [
    "d /app/data 0750 network-optimizer network-optimizer -"
  ];

  systemd.services.network-optimizer = {
    description = "Network Optimizer for UniFi";
    wantedBy = [ "multi-user.target" ];
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];

    # iperf3/sshpass: LAN speed tests + SSH to UniFi devices.
    # iputils/traceroute: latency probes and upstream path discovery.
    path = with pkgs; [ iperf3 sshpass traceroute iputils ];

    environment = {
      DOTNET_RUNNING_IN_CONTAINER = "true";
      ASPNETCORE_URLS = "http://*:8042";
      HOME = "/app/data";
      HOST_IP = hostsLib.getIP "network-optimizer";
      REVERSE_PROXIED_HOST_NAME = "optm.${hostsLib.domain}";
      Iperf3Server__Enabled = "true";
    };

    serviceConfig = {
      User = "network-optimizer";
      Group = "network-optimizer";
      # ContentRoot = the publish dir so wwwroot (the Blazor UI) resolves.
      WorkingDirectory = "${package}/lib/network-optimizer";
      ExecStart = "${package}/bin/NetworkOptimizer.Web";
      Restart = "always";
      RestartSec = 10;
      # Raw sockets for probes; must not combine with NoNewPrivileges.
      # why: docs/notes.md#network-optimizer
      AmbientCapabilities = "CAP_NET_RAW";
      CapabilityBoundingSet = "CAP_NET_RAW";
    };
  };
}
