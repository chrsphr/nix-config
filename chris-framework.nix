{ pkgs, pkgs-unstable ? pkgs, ... }:

{
  imports = [
    ./hardware/framework.nix
    ./modules/common-desktop.nix
    ./modules/luks-tpm.nix
    ./modules/btrfs-maintenance.nix
    ./modules/keyboard-backlight-timeout.nix
    ./modules/nfs-home-automount.nix
  ];

  # Hostname
  networking.hostName = "chris-framework";

  # Kernel sysctl settings for battery optimization
  boot.kernel.sysctl = {
    "kernel.nmi_watchdog" = 0;              # Disable watchdog interrupts
    "vm.dirty_writeback_centisecs" = 1500;  # Aggregate disk writes (15s)
  };

  # Audio codec power saving (revert to power_save=0 if clicking sounds occur)
  boot.extraModprobeConfig = ''
    options snd_hda_intel power_save=1
  '';

  boot.resumeDevice = "/dev/mapper/cryptroot";
  boot.kernelParams = [
    "mem_sleep_default=s2idle"
    "amdgpu.cwsr_enable=0"
    "pcie_aspm.policy=powersupersave"
    "resume_offset=533760"
  ];

  # AMD GPU / OpenCL
  hardware.graphics.extraPackages = with pkgs; [
    rocmPackages.clr.icd
    libvdpau-va-gl
  ];

  # Bluetooth firmware and driver support
  hardware.enableRedistributableFirmware = true;
  hardware.firmware = [ pkgs-unstable.linux-firmware ];
  boot.kernelModules = [ "btusb" "btrtl" ];

  # Power management
  services.power-profiles-daemon.enable = true;
  powerManagement.powertop.enable = true;  # Auto-tune power optimizations
  services.logind.settings.Login.HandleLidSwitch = "suspend-then-hibernate";
  services.logind.settings.Login.HandlePowerKey = "suspend-then-hibernate";
  services.logind.settings.Login.HandlePowerKeyLongPress = "poweroff";

  systemd.sleep.settings.Sleep = { HibernateDelaySec="30min";};

  # Skip the systemd-boot menu on cold boot (laptop only — no dual-boot).
  boot.loader.timeout = 0;

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

  systemd.tmpfiles.rules = [ "d /mnt/Media 0755 root root -" ];

  # Enable FUSE user mounts
  programs.fuse.userAllowOther = true;

  # Enable nix-ld for dynamically-linked binaries (uvx, etc.)
  programs.nix-ld.enable = true;
  programs.nix-ld.libraries = with pkgs; [
    cairo  # For remarkable-mcp notebook rendering
  ];
}
