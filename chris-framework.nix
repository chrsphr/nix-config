{ config, pkgs, pkgs-unstable ? pkgs, ... }:

{
  imports = [
    ./hardware/framework.nix
    ./modules/common.nix
  ];

  # Hostname
  networking.hostName = "chris-framework";

  # AMD AI 300 specific kernel parameters
  boot.kernelParams = [
    "mem_sleep_default=s2idle"
    "nvme_core.default_ps_max_latency_us=5500"
    "amdgpu.ppfeaturemask=0xffffffff"
  ];

  # Bluetooth firmware and driver support
  hardware.enableRedistributableFirmware = true;
  hardware.firmware = with pkgs; [ linux-firmware ];
  boot.kernelModules = [ "btusb" "btrtl" ];

  # Power management
  services.power-profiles-daemon.enable = true;
  services.logind.settings.Login.HandleLidSwitch = "suspend";
  services.logind.settings.Login.HandlePowerKey = "suspend";
  services.logind.settings.Login.HandlePowerKeyLongPress = "poweroff";

  # Fingerprint reader
  services.fprintd.enable = true;

  # Firmware updates
  services.fwupd.enable = true;

  # Enable FUSE user mounts
  programs.fuse.userAllowOther = true;


  # Framework-specific packages
  users.users.chris.packages = with pkgs; [
    fwupd
    gearlever
    appimage-run
    moonlight-qt
    lm_sensors
    amdgpu_top
    pkgs-unstable.darktable
    claude-code
  ];
}
