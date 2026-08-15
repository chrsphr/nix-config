{ config, pkgs, pkgs-unstable, sops-nix, gb-grid, gb-grid-pkg, lib, ... }:

let
  hostsLib = import ../lib/network.nix { inherit lib; };
  keys = import ../modules/keys.nix;

  # Containers that read the media library from the local ZFS pool. Guarded
  # below so they can't start against an empty dir if the pool didn't import.
  withMediaGuard = [ "immich" "plex" "sonarr" "transmission" ];
in
{
  imports = [
    ../modules/locale.nix
    # Host-level secrets (decrypted with hutch's own SSH host key).
    sops-nix.nixosModules.sops
    # NAS role: ZFS pool import, NFS, snapshots, encrypted B2 backup
    ../modules/nas.nix
    # LAN bond/bridge + every container with `parent = "hutch"`.
    ../modules/container-host.nix
    # Attaches the USB TV tuner physically plugged into minihutch.
    ../modules/usbip-tuner.nix
  ];

  # The tuner is projected from minihutch for the plex container below.
  # why: docs/notes.md#hutch
  usbipTuner.attach = {
    enable = true;
    server = hostsLib.getIP "minihutch";
    busid = "3-1";
    # Keep /dev/dvb present so plex's bind mount survives the tuner's absence.
    preCreate = [ "/dev/dvb" ];
  };
  # Newest ZFS-2.4.3-compatible kernel. why: docs/notes.md#kernel-pin
  boot.kernelPackages = pkgs.linuxPackages_6_18;

  # Cores reach C10, but the package stops at PC3 because the r8169 driver
  # disables ASPM on its own links. NOT a BIOS or _OSC problem — the NVMe on
  # the same bus runs ASPM L1 fine, and BIOS Native ASPM is already Enabled.
  # This param is not what fixes it; the fix is re-enabling L1 per link at
  # runtime. Kept because powersave is the right policy for a NAS anyway.
  # why: docs/notes.md#aspm-package-cstates
  boot.kernelParams = [ "pcie_aspm.policy=powersave" ];
  networking.hostName = "hutch";

  containerHost = {
    enable = true;
    # The Supermicro onboard NIC's MAC — fixed LAN identity for .2.
    macAddress = "0c:c4:7a:bd:45:32";

    # Onboard RTL8168h. Never cabled, so it added no redundancy while its
    # MII poll held root port #4 out of L1. enp4s0 (RTL8125B) is the uplink.
    excludePorts = [ "enp2s0" ];

    withSecrets = [ "gb-grid" "immich" ];

    # Per-container extras, merged over the defaults in container-host.nix.
    perContainer = {
      # The photo library, straight off the local ZFS pool.
      immich.bindMounts."/mnt/media/Photos" = {
        hostPath = "/mnt/Hutch/Media/Photos";
        isReadOnly = false;
      };

      # Read-only — Plex never writes media.
      plex.bindMounts = {
        "/media/Movies" = { hostPath = "/mnt/Hutch/Media/Movies"; isReadOnly = true; };
        "/media/Music"  = { hostPath = "/mnt/Hutch/Media/Music";  isReadOnly = true; };
        "/media/TV"     = { hostPath = "/mnt/Hutch/Media/TV";     isReadOnly = true; };
      };

      # The whole Media dataset, rw, at the path both apps are configured for.
      sonarr.bindMounts."/mnt/media" = {
        hostPath = "/mnt/Hutch/Media";
        isReadOnly = false;
      };
      transmission.bindMounts."/mnt/media" = {
        hostPath = "/mnt/Hutch/Media";
        isReadOnly = false;
      };

      # iGPU (QSV) transcode for plex + immich; verify with `vainfo` in each
      # container. char-DVB matches major 212, not the individual nodes —
      # absent-path DeviceAllow entries are silently dropped at unit load.
      # why: docs/notes.md#hutch
      plex.allowedDevices   = [
        { node = "/dev/dri/renderD128"; modifier = "rw"; }
        { node = "char-DVB";            modifier = "rw"; }
      ];
      plex.bindMounts."/dev/dri"   = { hostPath = "/dev/dri"; isReadOnly = false; };
      # The USB/IP tuner; /dev/dvb is pre-created so the mount always succeeds.
      plex.bindMounts."/dev/dvb"   = { hostPath = "/dev/dvb"; isReadOnly = false; };
      immich.allowedDevices = [ { node = "/dev/dri/renderD128"; modifier = "rw"; } ];
      immich.bindMounts."/dev/dri" = { hostPath = "/dev/dri"; isReadOnly = false; };
    };
  };

  # Media containers can't start against an unmounted (empty) library.
  # mkMerge, not `//` — plex is in both sets and `//` would drop the guard.
  # why: docs/notes.md#hutch
  systemd.services = lib.mkMerge [
    (lib.genAttrs (map (n: "container@${n}") withMediaGuard) (_: {
      requires = [ "zfs-mount.service" ];
      after = [ "zfs-mount.service" ];
      unitConfig.ConditionPathIsMountPoint = "/mnt/Hutch/Media";
    }))
    {
      # ExecStartPre, not tmpfiles: tmpfiles races container restarts on
      # deploy. why: docs/notes.md#hutch
      "container@plex".serviceConfig.ExecStartPre = [
        "${pkgs.coreutils}/bin/mkdir -p /dev/dvb"
      ];
    }
  ];

  # Boot loader
  boot.loader = {
    systemd-boot.enable = true;
    efi.canTouchEfiVariables = true;
  };

  # SSH + deploy user for deploy-rs. Keys only — both options stated on
  # purpose. why: docs/notes.md#hutch
  services.openssh = {
    enable = true;
    openFirewall = true;
    settings = {
      PermitRootLogin = "no";
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
    };
  };
  users.users.deploy = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    openssh.authorizedKeys.keys = [ keys.chris ];
  };
  # chris: interactive login. uid fixed; password set imperatively on the box
  # on purpose. why: docs/notes.md#hutch
  users.users.chris = {
    isNormalUser = true;
    uid = 1001;
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
