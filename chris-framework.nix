{ pkgs, pkgs-unstable ? pkgs, lib, ... }:

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

  # CachyOS optimized kernel (x86-64-v4 / AVX-512, matches Zen 5 Strix Point).
  # Overrides common-desktop.nix's linuxPackages_latest. The cachyosKernels set
  # comes from the nix-cachyos-kernel `pinned` overlay applied in flake.nix.
  boot.kernelPackages = lib.mkForce pkgs.cachyosKernels.linuxPackages-cachyos-latest-x86_64-v4;

  # Upstream's binary cache so the kernel is fetched, not compiled from source.
  # NOTE: these must already be active before the kernel build is evaluated. On
  # the FIRST switch that introduces both, pass them on the CLI instead, e.g.:
  #   nixos-rebuild switch --flake .#chris-framework \
  #     --option extra-substituters https://attic.xuyh0120.win/lantian \
  #     --option extra-trusted-public-keys lantian:EeAUQ+W+6r7EtwnmYjeVwx5kOGEBpjlBfPlzGlTNvHc=
  nix.settings.substituters = [ "https://attic.xuyh0120.win/lantian" ];
  nix.settings.trusted-public-keys = [ "lantian:EeAUQ+W+6r7EtwnmYjeVwx5kOGEBpjlBfPlzGlTNvHc=" ];

  # Kernel sysctl settings for battery optimization
  boot.kernel.sysctl = {
    "kernel.nmi_watchdog" = 0;              # Disable watchdog interrupts
    "vm.dirty_writeback_centisecs" = 1500;  # Aggregate disk writes (15s)
  };

  # Audio codec power saving (revert to power_save=0 if clicking sounds occur)
  boot.extraModprobeConfig = ''
    options snd_hda_intel power_save=1
    # Enable U-APSD (trigger-based Wi-Fi power save) on the Intel AX210. Lowers
    # idle radio power vs. the iwlwifi default of uapsd_disable=3. Revert to 3 if
    # the AP misbehaves (latency spikes, disconnects on power-save negotiation).
    options iwlwifi uapsd_disable=0
  '';

  boot.resumeDevice = "/dev/mapper/cryptroot";
  boot.kernelParams = [
    "mem_sleep_default=s2idle"
    "amdgpu.cwsr_enable=0"
    "pcie_aspm.policy=powersupersave"
    "resume_offset=533760"
    # Adaptive Backlight Management — disabled. It's content-adaptive (not
    # ambient): level 3 caused visible backlight flicker / brightness drift on
    # changing content. Confirmed stable with ABM off, so keep it off. Raise to
    # 1 (barely perceptible) if the battery saving is ever worth revisiting.
    "amdgpu.abmlevel=2"
    # Re-enable Panel Self-Refresh. nixos-hardware's framework-amd-ai-300-series
    # module disables PSR via dcdebugmask=0x10 (DC_DISABLE_PSR) for historical
    # panel flicker, but on this kernel/Mesa PSR is reliable and saves ~1W on
    # static content (reading, light browsing). This lands after nixos-hardware's
    # param on the cmdline, so last-wins re-enables it. Revert to 0x10 if any
    # flickering or corruption appears on the internal panel.
    "amdgpu.dcdebugmask=0x0"
    # Compressed swap cache in front of the swapfile (hibernate-compatible,
    # unlike zram) so memory pressure doesn't go straight to NVMe.
    "zswap.enabled=1"
    "zswap.compressor=zstd"
    "zswap.zpool=zsmalloc"
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

  # Intel AX210 (iwlwifi) Wi-Fi power save (revert if home Wi-Fi latency spikes)
  networking.networkmanager.wifi.powersave = true;

  # Cap charge at 90% to extend battery cycle life (framework_laptop EC driver).
  # Bump to 100 before a trip with: echo 100 | sudo tee /sys/class/power_supply/BAT1/charge_control_end_threshold
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

  # Smooth ambient-light brightness, replacing GNOME's choppy auto-brightness
  # (disabled in home/framework.nix). clight reads the panel ALS (iio:device0)
  # via clightd and fades the backlight along a tuned curve instead of stepping
  # it abruptly. Only the backlight module is used — gamma (colour temp),
  # dimmer, dpms, screen-content and keyboard tools are left to GNOME and the
  # keyboard-backlight-timeout module. geoclue2 (already enabled) gives clight
  # the day/night classification it needs to pick its capture timeouts.
  location.provider = "geoclue2";
  services.clight = {
    enable = true;
    settings = {
      gamma.disabled = true;
      dimmer.disabled = true;
      dpms.disabled = true;
      screen.disabled = true;
      keyboard.disabled = true;

      sensor = {
        # The Framework panel ALS, so clightd doesn't grab the webcam instead.
        devname = "iio:device0";
        # Average 5 ALS polls per calibration (AC, BATT) to smooth out noise.
        captures = [ 5 5 ];
      };

      backlight = {
        # The real fix for choppiness: fade every change over a fixed 1.2s
        # instead of GNOME's coarse jumps (overrides trans_step/trans_timeout).
        trans_fixed = 1200;
        # Re-check ambient light every [day, night, event] seconds. Kept equal
        # per state so day/night classification doesn't alter responsiveness.
        ac_timeouts = [ 6 6 6 ];
        batt_timeouts = [ 12 12 12 ];
        # Discard near-dark captures (e.g. a covered sensor) so brightness
        # doesn't dip to zero on a spurious reading.
        shutter_threshold = 0.05;
      };
    };
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
  users.users.chris.extraGroups = [ "docker" ];
}
