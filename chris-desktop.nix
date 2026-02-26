{ config, pkgs, lib, ... }:

{
  imports = [
    ./hardware/desktop.nix
    ./modules/common.nix
  ];

  # Hostname
  networking.hostName = "chris-desktop";

  # Desktop-specific kernel modules
  boot.kernelModules = [ "sg" ];

  # AMD GPU configuration
  hardware.amdgpu = {
    initrd.enable = true;
    opencl.enable = true;
  };

  # PipeWire wireplumber
  services.pipewire.wireplumber.enable = true;

  # CIFS mount to media server
  fileSystems."/home/chris/Media" = {
    device = "//lilnas.mcneill.fyi/Media";
    fsType = "cifs";
    options = let
      automount_opts = "x-systemd.automount,noauto,x-systemd.idle-timeout=60,x-systemd.device-timeout=5s,mount-timeout=5s";
    in ["${automount_opts},username=chris,uid=1000,gid=100,vers=3.0"];
  };

  # NFS configuration
  boot.supportedFilesystems = [ "nfs" ];
  services.rpcbind.enable = true;
  fileSystems."/mnt/Media" = {
    device = "192.168.1.12:/mnt/Hutch/Media";
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
  systemd.automounts = [{
    wantedBy = [ "multi-user.target" ];
    automountConfig = {
      TimeoutIdleSec = "600";
    };
    where = "/mnt/Media";
  }];

  # Gamescope configuration
  programs.gamescope = {
    enable = true;
    capSysNice = true;
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

  # Sunshine streaming (config only, we run it inside Gamescope)
  services.sunshine = {
    enable = true;
    autoStart = false;  # We start it manually inside Gamescope
    capSysAdmin = true;
    openFirewall = true;
    applications = {
      apps = [
        {
          name = "Steam";
          detached = [ "steam -gamepadui" ];
          image-path = "steam.png";
        }
      ];
    };
  };

  # Gamescope + Sunshine streaming session
  systemd.user.services.gamescope-sunshine = {
    description = "Gamescope Streaming Session with Sunshine";
    wantedBy = [ "graphical-session.target" ];
    partOf = [ "graphical-session.target" ];
    after = [ "graphical-session.target" ];

    path = [ pkgs.gamescope ];

    script = ''
      # Run Gamescope as a nested Wayland compositor with Sunshine inside
      # Sunshine will capture the Gamescope session, not your desktop
      exec gamescope \
        -W 2560 -H 1440 \
        -w 2560 -h 1440 \
        -r 60 \
        --nested-refresh 60 \
        --nested-unfocused-refresh 60 \
        --expose-wayland \
        -- ${config.security.wrapperDir}/sunshine
    '';

    serviceConfig = {
      Restart = "on-failure";
      RestartSec = 5;
    };
  };

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
  ];

  # Liquidctl udev rules for NZXT fan/RGB control
  services.udev.packages = [ pkgs.liquidctl ];
}
