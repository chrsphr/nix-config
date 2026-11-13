{ config, pkgs, lib, network, ... }:

# Gokapi file sharing as a NixOS container on hutch, on VLAN 5.
# Caddy (VLAN 1) is the only permitted ingress; links are random 20-char IDs.
# Data lives in /var/lib/gokapi inside this container root, so it is covered
# by the nightly container snapshot. Do not add a host bind mount here without
# reading the privateUsers note in hosts/hutch.nix.

let
  # Caddy keeps a static IP, so it can be matched exactly. Prometheus and
  # cloudflared are DHCP now, so match their subnets: VLAN 1 for Prometheus,
  # and VLAN 5 for cloudflared (this container is the only other host there).
  caddyIP = network.getIP "caddy";
  lanCIDR = "192.168.1.0/24";
  vlanCIDR = "192.168.6.0/24";
in
{
  # Static UID: Gokapi persists its SQLite DB and config in the state
  # directory, and DynamicUser's UID is not stable across container restarts.
  # With privateUsers in play that showed up as "permission denied" on the
  # old dynamic-UID files. Keep this UID when moving the data directory.
  users.groups.gokapi.gid = 3002;
  users.users.gokapi = {
    isSystemUser = true;
    uid = 3002;
    group = "gokapi";
  };

  networking = {
    # common.nix opens 22; do NOT add 53842 to allowedTCPPorts. Only Caddy
    # may reach the app port, even inside VLAN 5.
    firewall.extraCommands = ''
      iptables -A nixos-fw -s ${caddyIP} -p tcp --dport 53842 -j nixos-fw-accept
      iptables -A nixos-fw -s ${vlanCIDR} -p tcp --dport 53842 -j nixos-fw-accept
      iptables -A nixos-fw -s ${lanCIDR} -p tcp --dport 9100 -j nixos-fw-accept
    '';
  };

  # common.nix opens 9100 to the whole VLAN. Narrow it to Prometheus so the
  # VLAN firewall only needs one monitoring exception.
  services.prometheus.exporters.node.openFirewall = lib.mkForce false;

  services.gokapi = {
    enable = true;
    settings = {
      # Setup defaults this to the upstream GitHub project; point the index at
      # the local login page instead.
      RedirectUrl = "/login";
    };
    environment = {
      GOKAPI_PORT = 53842;
      # Both ingress paths: Caddy on VLAN 1 and the Cloudflare Tunnel
      # sidecar on the same VLAN. Gokapi accepts IPs and CIDRs here.
      GOKAPI_TRUSTED_PROXIES = "${caddyIP},${vlanCIDR}";
      GOKAPI_USE_CLOUDFLARE = "true";
      # Default is 15 (~90 bits); 20 is cheap extra entropy.
      GOKAPI_LENGTH_ID = 20;
      # 20 GiB per file, and refuse uploads when the container disk is low.
      GOKAPI_MAX_FILESIZE = 20480;
      GOKAPI_MIN_FREE_SPACE = 10240;
      GOKAPI_LOG_STDOUT = "true";
    };
  };

  # The module already uses DynamicUser/PrivateTmp/StateDirectory. Tighten the
  # rest; Gokapi only needs its state/cache directories and TCP sockets.
  systemd.services.gokapi.serviceConfig = {
    # See the static UID above; do not let systemd migrate the data directory
    # to a new dynamic UID on every restart.
    DynamicUser = lib.mkForce false;
    User = "gokapi";
    Group = "gokapi";

    # Gokapi stores a relative DatabaseUrl (`sqlite://./data/...`) once setup
    # has run. Without this, a restart resolves `data` against `/`, which is
    # read-only under ProtectSystem=strict.
    WorkingDirectory = "/var/lib/gokapi";
    ProtectSystem = "strict";
    ProtectHome = true;
    PrivateDevices = true;
    NoNewPrivileges = true;
    RestrictAddressFamilies = [ "AF_UNIX" "AF_INET" "AF_INET6" ];
    RestrictNamespaces = true;
    RestrictRealtime = true;
    RestrictSUIDSGID = true;
    LockPersonality = true;
    SystemCallArchitectures = "native";
    UMask = "0077";
  };
}
