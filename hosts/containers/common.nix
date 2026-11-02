{ config, pkgs, lib, ... }:

let
  keys = import ../../modules/keys.nix;
  hostsLib = import ../../lib/network.nix { inherit lib; };
  hostCfg = hostsLib.hosts.${config.networking.hostName} or {};
  isStatic = hostCfg ? ip;
in
{
  # Shared base for every NixOS container (systemd-nspawn) on both hosts.

  system.stateVersion = "26.05";

  # Nix settings
  nix.settings = {
    experimental-features = [ "nix-command" "flakes" ];
    sandbox = false;
    require-sigs = false;
  };
  nix.optimise.automatic = true;
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 7d";
  };

  documentation.enable = false;

  # Static-IP containers configure defaultGateway directly; DHCP containers
  # override nixos-containers.nix's `networking.useDHCP = false` and get their
  # IP, route and Option 12 hostname registration (<name>.internal) from the
  # UniFi DHCP server via dhcpcd.
  # why: docs/notes.md#container-one-offs
  networking = {
    nameservers = hostCfg.nameservers or hostsLib.nameservers;
    useDHCP = lib.mkForce (!isStatic);
    interfaces.eth0.useDHCP = !isStatic;
    defaultGateway = lib.mkIf isStatic {
      address = hostCfg.gateway or hostsLib.gateway;
      interface = "eth0";
    };
    dhcpcd = lib.mkIf (!isStatic) {
      # Wait for an IPv4 lease before forking; default "any" exits as soon as
      # IPv6 SLAAC completes, which can race services binding or resolving at boot.
      wait = "ipv4";
      extraConfig = ''
        # Send bare MAC as ClientID so UniFi matches reservations/leases cleanly
        clientid
      '';
    };
    firewall = {
      enable = true;
      allowedTCPPorts = [ 22 ];
    };
  };

  # The host's resolved stub is dead inside nspawn — use our own nameservers.
  # Also order nscd after resolvconf: nspawn copies the host's stub
  # /etc/resolv.conf into the container root before boot, so if nsncd starts
  # before resolvconf.service overwrites it, nsncd caches 127.0.0.53 and every
  # lookup times out.
  # why: docs/notes.md#container-one-offs
  networking.useHostResolvConf = lib.mkForce false;
  systemd.services.nscd = {
    after = [ "resolvconf.service" ];
    wants = [ "resolvconf.service" ];
  };

  # SSH setup
  services.openssh = {
    enable = true;
    openFirewall = true;
    settings = {
      PermitRootLogin = "no";
      PasswordAuthentication = false;
    };
  };

  # Create deploy user
  users.users.deploy = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    openssh.authorizedKeys.keys = [ keys.chris ];
  };
  users.users.root.openssh.authorizedKeys.keys = [ keys.chris ];
  security.sudo.wheelNeedsPassword = false;

  # Basic packages
  environment.systemPackages = with pkgs; [
    vim
    wget
    curl
    git
    htop
  ];

  # Timezone and locale
  time.timeZone = "Europe/London";
  i18n.defaultLocale = "en_GB.UTF-8";

  # Common group for media access
  users.groups.media = {};

  # Per-container systemd + network metrics and journal shipping to the
  # prometheus container. Host-level CPU/RAM/filesystem collectors are
  # disabled here to avoid scraping the parent kernel 12 times.
  # why: docs/notes.md#prometheus-and-journal-remote
  services.prometheus.exporters.node = {
    enable = true;
    openFirewall = true;
    extraFlags = [ "--collector.disable-defaults" ];
    enabledCollectors = [ "systemd" "netdev" ];
  };
  services.journald.upload = {
    enable = true;
    settings.Upload.URL = "http://${hostsLib.getIP "prometheus"}:19532";
  };
  # A receiver restart makes the uploader exit; restart it straight away so it
  # is back in `active` before switch-to-configuration checks unit states.
  # With RestartSec=3 (the NixOS default) it sits in activating (auto-restart)
  # during the check, which counts as failed and rolls the deploy back.
  # StartLimitIntervalSec=0 keeps a longer outage from tripping the burst cap.
  systemd.services.systemd-journal-upload = {
    unitConfig.StartLimitIntervalSec = 0;
    serviceConfig.RestartSec = lib.mkForce 0;
  };

  nixpkgs.config.allowUnfree = true;
}
