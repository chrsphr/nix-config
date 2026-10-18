{ config, pkgs, lib, ... }:

let
  keys = import ../../modules/keys.nix;
  hostsLib = import ../../lib/network.nix { inherit lib; };
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

  # Default gateway required under hostBridge. why: docs/notes.md#container-one-offs
  networking = {
    inherit (hostsLib) nameservers;
    defaultGateway = {
      address = hostsLib.gateway;
      interface = "eth0";
    };
    firewall = {
      enable = true;
      allowedTCPPorts = [ 22 ];
    };
  };

  # The host's resolved stub is dead inside nspawn — use our own nameservers.
  # why: docs/notes.md#container-one-offs
  networking.useHostResolvConf = lib.mkForce false;

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
  systemd.services.systemd-journal-upload.unitConfig.StartLimitIntervalSec = 0;

  nixpkgs.config.allowUnfree = true;
}
