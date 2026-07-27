{ lib, pkgs, pkgs-unstable ? pkgs, ... }:

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

  # Kernel: mainline linuxPackages_latest, inherited from common-desktop.nix.

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
  boot.kernelParams = lib.mkMerge [
    [
      "mem_sleep_default=s2idle"
      # CPPC preferred-core ranking. The firmware advertises differentiated cores
      # (Zen 5 highest_perf ~196-208 vs Zen 5c ~135), so amd-pstate can steer
      # bursty/foreground work onto the cores that boost highest. The kernel
      # parameter is "amd_prefcore" (NOT amd_pstate.prefcore); default is enabled
      # but /sys/devices/system/cpu/amd_pstate/prefcore read "disabled", so request
      # it explicitly. If it still reads "disabled" after a rebuild+reboot, it's a
      # Krackan Point / amd-pstate driver quirk, not this config or the BIOS.
      "amd_prefcore=enable"
      "amdgpu.cwsr_enable=0"
      "pcie_aspm.policy=powersupersave"
      "resume_offset=533760"
      # Adaptive Backlight Management — disabled. It's content-adaptive (not
      # ambient): level 3 caused visible backlight flicker / brightness drift on
      # changing content. Confirmed stable with ABM off, so keep it off. Raise to
      # 1 (barely perceptible) if the battery saving is ever worth revisiting.
      #"amdgpu.abmlevel=2"
      # Compressed swap cache in front of the swapfile (hibernate-compatible,
      # unlike zram) so memory pressure doesn't go straight to NVMe.
      "zswap.enabled=1"
      "zswap.compressor=zstd"
      "zswap.zpool=zsmalloc"
      # Lazy RCU: offload RCU callbacks and batch non-urgent ones to cut idle
      # wakeups (reduces idle power; used by ChromeOS). Reported as a measurable
      # battery win on the Framework AMD battery-tuning thread.
      "rcu_nocbs=all"
      "rcutree.enable_rcu_lazy=1"
    ]
    # Re-enable Panel Self-Refresh. nixos-hardware's framework-amd-ai-300-series
    # module disables PSR via dcdebugmask=0x10 (DC_DISABLE_PSR) for historical
    # panel flicker, but on this kernel/Mesa PSR is reliable and saves ~1W on
    # static content (reading, light browsing). Both params end up on the
    # cmdline and the kernel takes the last one, so this has to be appended
    # after nixos-hardware's — mkAfter guarantees that instead of leaving it to
    # module evaluation order. Check that dcdebugmask=0x0 is the last
    # dcdebugmask token in /proc/cmdline after a rebuild+reboot. Revert to 0x10
    # if any flickering or corruption appears on the internal panel.
    (lib.mkAfter [ "amdgpu.dcdebugmask=0x0" ])
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

  # Power management. powertop auto-tune deliberately NOT enabled: it blanket-
  # enables USB autosuspend (input-device stutter after idle) and re-applies
  # knobs that power-profiles-daemon then manages differently — let ppd own
  # runtime power policy.
  services.power-profiles-daemon.enable = true;

  # BlueZ's FastConnectable shortens the page-scan interval so the adapter is
  # quicker to accept incoming connections; BlueZ's own main.conf documents it
  # as increasing power consumption, because the radio scans far more often
  # while idle. common-desktop.nix turns it on for the desktop, where it costs
  # nothing that matters — override it here. Set it back if reconnecting the
  # headset/mouse from sleep becomes noticeably slower.
  hardware.bluetooth.settings.General.FastConnectable = lib.mkForce false;

  # Socket-activate sshd instead of running it permanently. Nothing deploys to
  # the laptop (it isn't in hosts.nix, so it's not a deploy-rs node); this is
  # only ever an inbound convenience over Tailscale, which works identically
  # via socket activation.
  services.openssh.startWhenNeeded = true;

  # Disable avahi/mDNS: it runs constantly and adds idle wakeups for little
  # benefit here. Trade-off: no .local hostname resolution or auto-discovery of
  # printers/shares/cast devices. Re-enable if the NFS automount or printing
  # starts relying on mDNS.
  services.avahi.enable = false;

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
  # Hibernate disabled 2026-07-12: resume-from-hibernate corrupts amdgpu's TTM
  # LRU bulk-move state, hard-locking the machine on a later GPU submission
  # (ttm_lru_bulk_move_tail oops / list_del corruption in amdgpu_cs_ioctl).
  # 16 identical crashes since suspend-then-hibernate was enabled on 2026-05-29,
  # across kernels 7.0.10 through 7.1.3 — an upstream amdgpu bug, not a kernel
  # regression. pstore dumps: /var/lib/systemd/pstore/. Restore
  # suspend-then-hibernate + HibernateDelaySec once fixed upstream.
  services.logind.settings.Login.HandleLidSwitch = "suspend";
  services.logind.settings.Login.HandlePowerKey = "suspend";
  services.logind.settings.Login.HandlePowerKeyLongPress = "poweroff";

  # ...and the same reason applies to upower's critical-battery action, which
  # defaults to HybridSleep. HybridSleep writes a hibernation image before
  # suspending, so a flat battery resumes through the exact amdgpu TTM path
  # that hibernate was disabled to avoid. Power off instead — at 2% remaining
  # the machine is going down either way, and the swapfile/resume_offset wiring
  # stays in place for when hibernate can be turned back on.
  services.upower.criticalPowerAction = "PowerOff";

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
  #
  # enableOnBoot = false leaves dockerd socket-activated rather than resident:
  # the daemon (plus containerd and its shims) only starts when something
  # touches /var/run/docker.sock, which on a laptop that dev-shells occasionally
  # means it is not running at all most of the time. Containers created with
  # `--restart=always` will not come back by themselves under this setting —
  # the gb-grid compose stack is started by hand, so that's fine.
  virtualisation.docker.enable = true;
  virtualisation.docker.enableOnBoot = false;
  users.users.chris.extraGroups = [ "docker" ];
}
