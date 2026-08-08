{ config, pkgs, lib, ... }:

# Network Optimizer for UniFi (security audit, SQM, speed tests, monitoring)
# as a NixOS container on hutch. Built from source via
# pkgs/network-optimizer.nix — upstream ships no prebuilt Linux tarball of the
# web app (only the Windows MSI and the optional multi-site agent).
#
# UniFi controller creds are entered in the UI and stored encrypted in the
# SQLite DB. InfluxDB 2 (co-located, below) backs the Monitoring time-series:
# onboard it once via its UI on :8086 (admin user + all-access token), then
# paste the token into the app's Monitoring setup wizard.
#
# Deliberately not set up: the OpenSpeedTest sidecar on :3005, the WAN
# Steering daemon (tools/wansteer-*, single-WAN here), and the self-hosted
# Traefik/nginx proxy features (Caddy already fronts the UI).

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

  # Time-series store for the Monitoring features (SNMP device health,
  # latency/loss probes, ISP Health). No declarative provisioning in NixOS —
  # onboard once via the UI (see header comment). State lives in
  # /var/lib/influxdb2, inside the container root, so the nightly btrfs
  # container snapshots cover it.
  services.influxdb2.enable = true;

  users.users.network-optimizer = {
    isSystemUser = true;
    group = "network-optimizer";
  };
  users.groups.network-optimizer = { };

  # DOTNET_RUNNING_IN_CONTAINER=true makes the app keep ALL state (SQLite,
  # encrypted creds, data-protection keys, floor plans, exports) in /app/data,
  # matching upstream's docker layout — nothing writes under the (read-only,
  # store-resident) app dir. It also skips UseHttpsRedirection/HSTS, which is
  # correct behind Caddy.
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
      # ContentRoot defaults to the working directory; point it at the publish
      # dir so wwwroot (the whole Blazor UI) resolves. Read-only is fine —
      # see the DOTNET_RUNNING_IN_CONTAINER note above.
      WorkingDirectory = "${package}/lib/network-optimizer";
      ExecStart = "${package}/bin/NetworkOptimizer.Web";
      Restart = "always";
      RestartSec = 10;
      # Raw sockets for ping/traceroute probes. Must NOT be combined with
      # NoNewPrivileges: execve clears the ambient set when that's set.
      AmbientCapabilities = "CAP_NET_RAW";
      CapabilityBoundingSet = "CAP_NET_RAW";
    };
  };
}
