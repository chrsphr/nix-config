{ pkgs, pkgs-unstable ? pkgs, ... }:

{
  imports = [
    ./hardware/framework.nix
    ./modules/common.nix
    ./modules/keyboard-backlight-timeout.nix
    ./modules/nfs-home-automount.nix
  ];

  # Hostname
  networking.hostName = "chris-framework";

  # AMD AI 300 specific kernel parameters
  boot.kernelParams = [
    "mem_sleep_default=s2idle"
    "nvme_core.default_ps_max_latency_us=5500"
    "amdgpu.ppfeaturemask=0xffffffff"
  ];

  # Resume device for hibernate (must match swap partition)
  boot.resumeDevice = "/dev/disk/by-uuid/94e97208-7c17-4f2a-87ea-2471dd708f1f";

  # AMD GPU / OpenCL
  hardware.amdgpu.opencl.enable = true;

  # Bluetooth firmware and driver support
  hardware.enableRedistributableFirmware = true;
  hardware.firmware = [ pkgs-unstable.linux-firmware ];
  boot.kernelModules = [ "btusb" "btrtl" ];

  # Power management
  services.power-profiles-daemon.enable = true;
  services.logind.settings.Login.HandleLidSwitch = "suspend-then-hibernate";
  services.logind.settings.Login.HandlePowerKey = "suspend-then-hibernate";
  services.logind.settings.Login.HandlePowerKeyLongPress = "poweroff";

  # Hibernate after 15 minutes of sleep
  systemd.sleep.extraConfig = ''
    HibernateDelaySec=15min
  '';

  # Keyboard backlight auto-timeout
  services.keyboard-backlight-timeout = {
    enable = true;
    timeout = 30;  # seconds
    brightnessMax = 100;
  };

  # Fingerprint reader
  services.fprintd.enable = true;

  # Firmware updates
  services.fwupd.enable = true;

  # Enable FUSE user mounts
  programs.fuse.userAllowOther = true;

  # Enable nix-ld for dynamically-linked binaries (uvx, etc.)
  programs.nix-ld.enable = true;
  programs.nix-ld.libraries = with pkgs; [
    cairo  # For remarkable-mcp notebook rendering
  ];
}
