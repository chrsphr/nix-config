{ config, pkgs, lib, network, ... }:

# Shared base for every NixOS container (systemd-nspawn) on both hosts.
# Imported for each container by modules/container-host.nix, which also sets
# networking.hostName (the container name) and, for containers listed in
# containerHost.withSecrets, the sops-nix module and its defaults.

let
  keys = import ../../modules/keys.nix;
  hostCfg = network.hosts.${config.networking.hostName} or {};
  isStatic = hostCfg ? ip;
in
{
  imports = [
    # Journal shipping to the prometheus container.
    ../../modules/journal-upload.nix
  ];

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
    nameservers = hostCfg.nameservers or network.nameservers;
    useDHCP = lib.mkForce (!isStatic);
    interfaces.eth0.useDHCP = !isStatic;
    defaultGateway = lib.mkIf isStatic {
      address = hostCfg.gateway or network.gateway;
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
    firewall.enable = true;
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

  # SSH setup (openFirewall opens 22)
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

  # Per-container systemd + network metrics. Host-level CPU/RAM/filesystem
  # collectors are disabled here to avoid scraping the parent kernel 12 times.
  # why: docs/notes.md#prometheus-and-journal-remote
  services.prometheus.exporters.node = {
    enable = true;
    openFirewall = true;
    extraFlags = [ "--collector.disable-defaults" ];
    enabledCollectors = [ "systemd" "netdev" ];
  };

  nixpkgs.config.allowUnfree = true;
}
