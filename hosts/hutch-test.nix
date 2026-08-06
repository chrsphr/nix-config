{ config, pkgs, pkgs-unstable, sops-nix, lib, ... }:

let
  hostsLib = import ../lib/network.nix { inherit lib; };
  keys = import ../modules/keys.nix;
in
{
  imports = [
    ../modules/locale.nix
    # NAS role: ZFS pool import, NFS, snapshots, B2 sync (TrueNAS replacement)
    ../modules/nas.nix
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
    lib.nameValuePair name ({
      privateNetwork = true;
      hostBridge = "br0";
      localAddress = "${cfg.ip}/24";
      autoStart = true;
      specialArgs = { inherit pkgs-unstable; };
      config = { imports = [ (./containers + "/${name}.nix") ]; };
    } // lib.optionalAttrs (name == "immich") {
      # Production immich, replacing the Proxmox LXC. autoStart stays false
      # until cutover — the LXC still owns 192.168.1.127. Starting it early
      # would also fail: the pool disks aren't attached yet.
      autoStart = false;
      specialArgs = { inherit pkgs-unstable sops-nix; };
      # The photo library lives on the local ZFS pool — bind it straight in
      # instead of the NFS loopback the LXC used (Proxmox host mounted
      # 192.168.1.12:/mnt/Hutch/Media over NFS, then bind-mounted that).
      bindMounts = {
        "/mnt/media/Photos" = {
          hostPath = "/mnt/Hutch/Media/Photos";
          isReadOnly = false;
        };
        # sops age key for secrets/immich.yaml — copy keys.txt from the LXC's
        # /home/deploy/.config/sops/age/keys.txt into this dir before cutover.
        "/var/secrets" = {
          hostPath = "/var/lib/sops-nix/immich";
          isReadOnly = true;
        };
      };
    })
  ) (hostsLib.getContainers "hutch-test");

  # Don't let the immich container start against an empty library if the pool
  # didn't import — nspawn would happily bind an empty host dir otherwise.
  systemd.services."container@immich" = {
    requires = [ "zfs-mount.service" ];
    after = [ "zfs-mount.service" ];
    unitConfig.ConditionPathIsMountPoint = "/mnt/Hutch/Media";
  };

  systemd.tmpfiles.rules = [
    "d /var/lib/sops-nix/immich 0700 root root -"
  ];

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
