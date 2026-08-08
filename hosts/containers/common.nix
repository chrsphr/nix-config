{ config, pkgs, lib, ... }:

let
  keys = import ../../modules/keys.nix;
  hostsLib = import ../../lib/network.nix { inherit lib; };
in
{
  # Shared base for NixOS containers (systemd-nspawn) running on hutch.
  # Analogous to common-lxc.nix but without the Proxmox LXC module.

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
    # Deterministic /etc/resolv.conf written straight from networking.nameservers
    # at activation (no resolvconf tool, no systemd-resolved stub — the host's
    # stub is what broke resolution; see useHostResolvConf=false in hutch.nix).
    useResolvconf = lib.mkForce false;
    firewall = {
      enable = true;
      allowedTCPPorts = [ 22 ];
    };
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

  nixpkgs.config.allowUnfree = true;
}
