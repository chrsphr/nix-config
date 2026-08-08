{ config, pkgs, lib, ... }:

let
  keys = import ../../modules/keys.nix;
  hostsLib = import ../../lib/network.nix { inherit lib; };
in
{
  # Shared base for every NixOS container (systemd-nspawn) on hutch.

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

  # Networking defaults. The default gateway is required: hostBridge puts the
  # container straight on the LAN, but without a default route it can't reply
  # to (or reach) anything off-subnet.
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

  # The container profile defaults networking.useHostResolvConf = true, so
  # resolvconf inside the container regenerates /etc/resolv.conf from the
  # HOST's copy — which is the systemd-resolved stub (127.0.0.53), and
  # resolved does not run inside the containers: every lookup fails (caddy:
  # "lookup acme-v02.api.letsencrypt.org: no such host"). Turn it off so
  # resolvconf writes the container's own networking.nameservers instead.
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

  nixpkgs.config.allowUnfree = true;
}
