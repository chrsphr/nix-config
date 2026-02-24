{ config, pkgs, ... }:

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

  # Sunshine streaming
  services.sunshine = {
    enable = true;
    autoStart = true;
    capSysAdmin = true;
    openFirewall = true;
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
  ];
}
