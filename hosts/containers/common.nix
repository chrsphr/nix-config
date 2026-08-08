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
    firewall = {
      enable = true;
      allowedTCPPorts = [ 22 ];
    };
  };

  # The host runs systemd-resolved (nixpkgs enables it when networking.useNetworkd
  # is on), so the host's /etc/resolv.conf is the 127.0.0.53 stub. The NixOS
  # container module copies the host's resolv.conf into the container on every
  # start (nixos-containers.nix: `cp /etc/resolv.conf "$root/etc/resolv.conf"`),
  # but systemd-resolved is NOT running inside the container — every lookup
  # fails (e.g. caddy: "dial tcp: lookup acme-v02.api.letsencrypt.org: no such
  # host"). Overwrite it with the container's own nameservers at boot: the
  # host's copy lands before nspawn boots, and systemd-tmpfiles runs after.
  systemd.tmpfiles.rules = let
    resolv = builtins.concatStringsSep "\n"
      (map (n: "nameserver ${n}") config.networking.nameservers) + "\n";
  in [
    "f /etc/resolv.conf 0644 root root - ${resolv}"
  ];

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
