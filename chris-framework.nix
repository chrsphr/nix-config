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
    "amdgpu.cwsr_enable=0"  # Disable CWSR to prevent MES firmware hangs
    "pcie_aspm.policy=powersupersave"  # Aggressive PCIe power states
  ];

  # Kernel sysctl settings for battery optimization
  boot.kernel.sysctl = {
    "kernel.nmi_watchdog" = 0;              # Disable watchdog interrupts
    "vm.dirty_writeback_centisecs" = 1500;  # Aggregate disk writes (15s)
  };

  # Audio codec power saving (revert to power_save=0 if clicking sounds occur)
  boot.extraModprobeConfig = ''
    options snd_hda_intel power_save=1
  '';

  # Hibernate resume: swapfile lives on the btrfs root (LUKS-backed).
  # resumeDevice = the device holding the swapfile (/dev/mapper/cryptroot);
  # resumeOffset is set by nixos-generate-config or computed with
  #   `btrfs inspect-internal map-swapfile -r /swap/swapfile`
  # Fill these in after install, then `nixos-rebuild switch`.
  # boot.resumeDevice = "/dev/mapper/cryptroot";
  # boot.kernelParams = [ "resume_offset=<offset>" ];

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

  # Hibernate after 15 minutes of sleep
  systemd.sleep.extraConfig = ''
    HibernateDelaySec=15min
  '';

  #boot settings
  boot.loader.timeout = 0;
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # LUKS root with TPM2 auto-unlock (enrol with `systemd-cryptenroll` post-install).
  boot.initrd.systemd.enable = true;
  boot.initrd.systemd.tpm2.enable = true;
  boot.initrd.luks.devices.cryptroot = {
    device = "/dev/disk/by-partlabel/luks";
    allowDiscards = true;
    crypttabExtraOpts = [ "tpm2-device=auto" ];
  };
  security.tpm2.enable = true;
  environment.systemPackages = [ pkgs.tpm2-tools ];

  # Btrfs maintenance
  services.btrfs.autoScrub = {
    enable = true;
    interval = "monthly";
    fileSystems = [ "/" ];
  };
  # discard=async handles TRIM at free-time; fstrim timer is a belt-and-braces
  # weekly sweep for anything missed (e.g. on /boot vfat).
  services.fstrim.enable = true;

  # Nix store hardlink dedup — meaningful savings on /nix independent of FS.
  nix.settings.auto-optimise-store = true;

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
