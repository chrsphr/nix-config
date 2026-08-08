{ config, pkgs, pkgs-unstable ? pkgs, ... }:

{
  imports = [
    ../hardware/desktop.nix
    ../modules/common-desktop.nix
    ../modules/luks-tpm.nix
    ../modules/btrfs-maintenance.nix
  ];

  # Hostname
  networking.hostName = "chris-desktop";

  # Skip the systemd-boot menu on boot.
  boot.loader.timeout = 0;

  # Desktop-specific kernel modules
  boot.kernelModules = [ "sg" ];

  # Hibernate: resume from the btrfs swapfile inside LUKS. resume_offset is the
  # physical offset of /swap/swapfile, from `btrfs inspect-internal map-swapfile`.
  boot.resumeDevice = "/dev/mapper/cryptroot";
  boot.kernelParams = [
    "resume_offset=533760"
    # Compressed swap cache in front of the swapfile (hibernate-compatible,
    # unlike zram) so memory pressure doesn't go straight to NVMe.
    "zswap.enabled=1"
  ];

  # AMD GPU configuration
  hardware.amdgpu = {
    initrd.enable = true;
  };

  # Enable Rusticl OpenCL backend for radeonsi (GFX12/RDNA4). The RUSTICL_ENABLE
  # env var is useless without the ICD, so also ship mesa.opencl so the loader
  # (ocl-icd, used by darktable) can find it under /run/opengl-driver.
  hardware.graphics.extraPackages = with pkgs; [
    mesa.opencl
  ];
  environment.variables.RUSTICL_ENABLE = "radeonsi";

  # PipeWire wireplumber
  services.pipewire.wireplumber.enable = true;

  # NFS media share — x-systemd.automount in mount options is sufficient;
  # it auto-generates the .automount unit. Idle timeout is set inline.
  boot.supportedFilesystems = [ "nfs" ];
  services.rpcbind.enable = true;
  systemd.tmpfiles.rules = [ "d /mnt/Media 0755 root root -" ];
  fileSystems."/mnt/Media" = {
    device = "192.168.1.2:/mnt/Hutch/Media";
    fsType = "nfs";
    options = [
      "x-systemd.automount"
      "noauto"
      "x-systemd.idle-timeout=600"
      "x-systemd.requires=network-online.target"
      "x-systemd.device-timeout=10s"
      "x-systemd.mount-timeout=10s"
      "soft"
      "timeo=10"
      "retrans=2"
      "nofail"
      "_netdev"
    ];
  };

  # Gamescope configuration
  programs.gamescope = {
    enable = true;
    capSysNice = false; # workaround for nixpkgs#523200, re-enable when #524488 lands
  };
  programs.steam.gamescopeSession.enable = true;

  # Open port for Immich ML service
  networking.firewall.allowedTCPPorts = [ 3003 ];

  # Virtualization
  virtualisation.libvirtd.enable = true;
  virtualisation.docker.enable = true;
  programs.virt-manager.enable = true;

  # Desktop-specific user groups
  users.users.chris.extraGroups = [ "docker" "libvirtd" "cdrom" "arm" ];
  users.groups = {
    libvirtd.members = [ "chris" ];
    kvm.members = [ "chris" ];
  };

  # Sunshine streaming. Pull the package from unstable — nixpkgs lags upstream
  # badly (stable & unstable both sat on 2025.924 for months; see nixpkgs
  # #524668), so this picks up newer builds on `nix flake update` without moving
  # the rest of the host off stable.
  services.sunshine = {
    enable = true;
    package = pkgs-unstable.sunshine;
    autoStart = true;
    capSysAdmin = true;
    openFirewall = true;
  };

  # autoStart wires the user unit to graphical-session.target, which the GDM
  # greeter session (user "gdm-greeter", a high UID) also reaches — so Sunshine
  # launches there first, grabs port 48010, and the real login's instance fails
  # to bind ("RTSP server ... Address already in use"). Restrict it to chris.
  systemd.user.services.sunshine.unitConfig.ConditionUser = "chris";

  # CPU EPP: GNOME's power-profiles-daemon already sets balance_performance on
  # the default "balanced" profile (and re-asserts it on profile changes), so no
  # custom oneshot is needed here.

  # Feral GameMode — on-demand performance for games (opt-in per title).
  programs.gamemode.enable = true;

  # Wake-on-LAN on the wired NIC. Also enable "Power On by PCIE/LAN" (or
  # equivalent) in BIOS for wake from full power-off.
  networking.interfaces.eno1.wakeOnLan.enable = true;

  # Disable problematic wake sources
  systemd.services.disable-wake-sources = {
    description = "Disable USB wake sources";
    wantedBy = [ "multi-user.target" ];
    after = [ "multi-user.target" ];
    script = ''
      echo GPP0 > /proc/acpi/wakeup
      echo GPP8 > /proc/acpi/wakeup

    '';
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
  };

  # System packages for desktop
  environment.systemPackages = with pkgs; [
    ffmpeg-full
    liquidctl
    ethtool
  ];

  # Liquidctl udev rules for NZXT fan/RGB control
  services.udev.packages = [ pkgs.liquidctl ];
}
