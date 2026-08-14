{ pkgs, ... }:

{
  imports = [
    ../hardware/framework.nix
    ../modules/common-desktop.nix
    ../modules/luks-tpm.nix
    ../modules/btrfs-maintenance.nix
    ../modules/keyboard-backlight-timeout.nix
    ../modules/nfs-home-automount.nix
  ];

  networking.hostName = "chris-framework";

  # Battery tuning throughout this file. why: docs/notes.md#framework-power-tuning

  # Kernel sysctl settings for battery optimization
  boot.kernel.sysctl = {
    "kernel.nmi_watchdog" = 0;              # Disable watchdog interrupts
    "vm.dirty_writeback_centisecs" = 1500;  # Aggregate disk writes (15s)
  };

  # Audio codec power saving (revert to power_save=0 if clicking sounds occur)
  boot.extraModprobeConfig = ''
    options snd_hda_intel power_save=1
    # Enable U-APSD (trigger-based Wi-Fi power save) on the Intel AX210 (swapped
    # in for the stock MT7925). uapsd_disable is a bitmask: 3 = disabled on
    # BSS+P2P (the driver default), 0 = enabled. Lowers idle radio power; revert
    # to 3 if the AP misbehaves (latency spikes, disconnects on power-save
    # negotiation).
    options iwlwifi uapsd_disable=0
  '';

  boot.resumeDevice = "/dev/mapper/cryptroot";
  boot.kernelParams = [
    "mem_sleep_default=s2idle"
    # No amd_prefcore (confirmed no-op on Krackan Point) and no abmlevel
    # (flicker). why: docs/notes.md#framework-power-tuning
    "amdgpu.cwsr_enable=0"
    "pcie_aspm.policy=powersupersave"
    "resume_offset=533760"
    # Re-enable PSR, overriding nixos-hardware's dcdebugmask=0x10; revert to
    # 0x10 if the internal panel flickers.
    "amdgpu.dcdebugmask=0x0"
    # Compressed swap cache (hibernate-compatible, unlike zram).
    "zswap.enabled=1"
    # Lazy RCU: fewer idle wakeups.
    "rcu_nocbs=all"
    "rcutree.enable_rcu_lazy=1"
  ];

  # AMD GPU / OpenCL
  hardware.graphics.extraPackages = with pkgs; [
    libvdpau-va-gl
    mesa.opencl  # Rusticl ICD — makes the AMD GPU visible to OpenCL apps (darktable)
  ];

  # Rusticl needs the gallium driver selection; radeonsi covers RDNA iGPUs.
  environment.variables.RUSTICL_ENABLE = "radeonsi";

  # Bluetooth firmware and driver support
  hardware.enableRedistributableFirmware = true;
  boot.kernelModules = [ "btusb" "btrtl" ];

  # ppd owns runtime power policy; powertop auto-tune deliberately not enabled.
  services.power-profiles-daemon.enable = true;

  # Targeted PCI runtime PM for the NVMe only (benefit unproven — see notes
  # Pending). No iwlwifi rule: the driver overrides it.
  # why: docs/notes.md#framework-power-tuning
  services.udev.extraRules = ''
    ACTION=="add", SUBSYSTEM=="pci", DRIVERS=="nvme", ATTR{power/control}="auto"
  '';

  # GNOME's file indexer: CPU + NVMe wakeups for a search feature unused here.
  services.gnome.localsearch.enable = false;

  # Firmware metadata refresh pulls over the network on a timer — on AC only.
  systemd.services.fwupd-refresh.unitConfig.ConditionACPower = true;

  # No .local resolution / printer discovery; fewer idle wakeups.
  services.avahi.enable = false;

  # OFF — caused latency spikes; U-APSD (modprobe config above) stays on.
  # history: docs/notes.md#2026-07-27-wifi-powersave-latency
  networking.networkmanager.wifi.powersave = false;

  # Cap charge at 90% to extend battery cycle life (framework_laptop EC driver).
  systemd.services.battery-charge-threshold = {
    description = "Set battery charge limit";
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      echo 90 > /sys/class/power_supply/BAT1/charge_control_end_threshold
    '';
  };
  # Hibernate disabled — amdgpu corruption on resume.
  # history: docs/notes.md#2026-07-12-hibernate-crash
  services.logind.settings.Login.HandleLidSwitch = "suspend";
  services.logind.settings.Login.HandlePowerKey = "suspend";
  services.logind.settings.Login.HandlePowerKeyLongPress = "poweroff";

  # Skip the systemd-boot menu on cold boot (laptop only — no dual-boot).
  boot.loader.timeout = 0;

  # Keyboard backlight auto-timeout
  services.keyboard-backlight-timeout = {
    enable = false;
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

  # Docker engine for local dev. The gb-grid `nix develop` shell brings its
  # Postgres + Grafana up via `docker compose`; merges with common-desktop's
  # chris groups.
  virtualisation.docker.enable = true;
  # Socket-activated: only wanted inside the gb-grid dev shell.
  virtualisation.docker.enableOnBoot = false;
  users.users.chris.extraGroups = [ "docker" ];

  # Cap the journal — write amplification on compressed btrfs.
  services.journald.extraConfig = "SystemMaxUse=500M";
}
