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
    # Host-level secrets. Unlike the containers, hutch decrypts with its own SSH
    # host key (sops.age.sshKeyPaths default) — nothing to place by hand.
    sops-nix.nixosModules.sops
    # NAS role: ZFS pool import, NFS, snapshots, encrypted B2 backup
    ../modules/nas.nix
    # LAN bond/bridge + every container with `parent = "hutch"`, plus the
    # btrfs container-root snapshots that come with it.
    ../modules/container-host.nix
    # Attaches the USB TV tuner physically plugged into minihutch.
    ../modules/usbip-tuner.nix
  ];

  # The TV tuner lives on minihutch (no free/reachable port on this box), but
  # Plex reads DVB tuners straight off /dev/dvb, so the device is projected
  # here over USB/IP and passed into the plex container below.
  usbipTuner.attach = {
    enable = true;
    server = hostsLib.getIP "minihutch";
    busid = "3-1";
    # Keep /dev/dvb present even when the tuner isn't attached, so plex's
    # bind mount always succeeds. Without this the whole media library would
    # fail to start whenever minihutch is down — coupling Plex's availability
    # to a live-TV accessory, which is the wrong way round.
    preCreate = [ "/dev/dvb" ];
  };
  # Newest kernel that is both supported by ZFS 2.4.3 (max 7.0) and not
  # EOL-removed in nixpkgs (7.0, 6.19, 6.17 all are; latest is 7.1).
  boot.kernelPackages = pkgs.linuxPackages_6_18;
  networking.hostName = "hutch";

  containerHost = {
    enable = true;
    # The Supermicro onboard NIC's MAC — fixed LAN identity for .2.
    macAddress = "0c:c4:7a:bd:45:32";

    # caddy and uptime moved to minihutch (2026-08-09) and took their key
    # requirement with them — see hosts/minihutch.nix.
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

      # QSV/hardware transcode for plex + immich. hutch's i5-12600K has a UHD
      # 770 iGPU and /dev/dri/renderD128 is present on the host, so exposing it
      # is just a bind mount + allowedDevices — no passthrough to arrange like
      # the old LXC dev0/dev1 gid mapping.
      #
      # The userspace half (hardware.graphics, intel-media-driver, vpl-gpu-rt,
      # video/render groups) already lives in the two container configs; the
      # host needs no hardware.graphics of its own, since each nspawn guest
      # builds its own /run/opengl-driver. Without these four lines both apps
      # silently transcode on CPU.
      #
      # Verify after deploy with `vainfo` inside each container — it should
      # report the iHD driver and H264/HEVC VLD+encode entrypoints.
      # char-DVB matches major 212 ("212 DVB" in /proc/devices) rather than
      # the individual frontend0/demux0/dvr0 nodes: those only exist while the
      # tuner is attached, and DeviceAllow entries for absent paths are
      # dropped at unit-load time — so naming them would silently deny access
      # on every boot where plex started before the tuner did.
      plex.allowedDevices   = [
        { node = "/dev/dri/renderD128"; modifier = "rw"; }
        { node = "char-DVB";            modifier = "rw"; }
      ];
      plex.bindMounts."/dev/dri"   = { hostPath = "/dev/dri"; isReadOnly = false; };
      # The DVB tuner, projected from minihutch over USB/IP (see
      # usbipTuner.attach above). /dev/dvb is pre-created on devtmpfs so this
      # mount succeeds whether or not the tuner is currently attached.
      plex.bindMounts."/dev/dvb"   = { hostPath = "/dev/dvb"; isReadOnly = false; };
      immich.allowedDevices = [ { node = "/dev/dri/renderD128"; modifier = "rw"; } ];
      immich.bindMounts."/dev/dri" = { hostPath = "/dev/dri"; isReadOnly = false; };
    };
  };

  # Don't let media containers start against an empty library if the pool
  # didn't import — nspawn would happily bind an empty host dir otherwise.
  # mkMerge, not `//`: plex appears in both sets, and `//` would replace its
  # whole definition rather than merging, silently dropping the mount guard.
  systemd.services = lib.mkMerge [
    (lib.genAttrs (map (n: "container@${n}") withMediaGuard) (_: {
      requires = [ "zfs-mount.service" ];
      after = [ "zfs-mount.service" ];
      unitConfig.ConditionPathIsMountPoint = "/mnt/Hutch/Media";
    }))
    {
    # nspawn refuses to start when a bindMount source is missing ("Failed to
    # clone /dev/dvb: No such file or directory"), and /dev/dvb only exists
    # while the USB/IP tuner is attached. usbipTuner.attach.preCreate covers
    # boot via tmpfiles, but that races on a `deploy`: switch-to-configuration
    # restarts container@plex and systemd-tmpfiles-resetup concurrently, which
    # is exactly how this failed the first time. Creating the directory in
    # ExecStartPre is ordered by construction — it cannot race, and it keeps
    # plex independent of whether the tuner or minihutch is actually up.
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

  # SSH + deploy user for deploy-rs
  # Keys only: PasswordAuthentication off, and KbdInteractiveAuthentication
  # off too — with UsePAM the latter would otherwise *advertise* a
  # keyboard-interactive path (blocked only by pam_deny in the sshd PAM
  # stack). Stating both makes keys-only unambiguous.
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
  # chris: interactive console/SSH login. uid must match the account created
  # on first setup (useradd -u 1001). No password option here on purpose —
  # the one set via chpasswd on the live box survives rebuilds, and keeps the
  # secret out of the repo; add initialHashedPassword if that ever changes.
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
