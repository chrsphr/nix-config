{ config, pkgs, pkgs-unstable, lib, ... }:

let
  hostsLib = import ../lib/network.nix { inherit lib; };
  keys = import ../modules/keys.nix;
in
{
  imports = [
    ../modules/locale.nix
  ];

  # VM hostname
  networking.hostName = "hutch-test";

  # eth0 is bridged into br0 so NixOS containers get LAN-reachable IPs via
  # hostBridge (same L2 as the rest of the 192.168.1.0/24 fleet).
  networking = {
    bridges.br0.interfaces = [ "eth0" ];
    interfaces.br0.ipv4.addresses = [{
      address = hostsLib.getIP "hutch-test";
      prefixLength = 24;
    }];
    defaultGateway = {
      address = hostsLib.gateway;
      interface = "br0";
    };
    inherit (hostsLib) nameservers;
    firewall.allowedTCPPorts = [ 22 ];
  };

  # NixOS containers, one per network.nix host with `parent = "hutch-test"`.
  # IPs, bridge and autostart all derive from lib/network.nix.
  containers = lib.mapAttrs' (name: cfg:
    lib.nameValuePair name {
      privateNetwork = true;
      hostBridge = "br0";
      localAddress = "${cfg.ip}/24";
      autoStart = true;
      specialArgs = { inherit pkgs-unstable; };
      config = { imports = [ (./containers + "/${name}.nix") ]; };
    }
  ) (hostsLib.getContainers "hutch-test");

  # Boot loader
  boot.loader = {
    systemd-boot.enable = true;
    efi.canTouchEfiVariables = true;
  };

  # SSH + deploy user for deploy-rs
  services.openssh = {
    enable = true;
    openFirewall = true;
    settings = {
      PermitRootLogin = "no";
      PasswordAuthentication = false;
    };
  };
  users.users.deploy = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    openssh.authorizedKeys.keys = [ keys.chris ];
  };
  users.users.root.openssh.authorizedKeys.keys = [ keys.chris ];
  security.sudo.wheelNeedsPassword = false;

  # Nix settings
  nix.settings = {
    experimental-features = [ "nix-command" "flakes" ];
    sandbox = false;
    require-sigs = false;
  };

  environment.systemPackages = with pkgs; [
    vim
    htop
    git
  ];

  nixpkgs.config.allowUnfree = true;
  system.stateVersion = "26.05";
}
