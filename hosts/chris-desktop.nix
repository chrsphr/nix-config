{ config, pkgs, pkgs-unstable ? pkgs, ... }:

{
  imports = [
    ../hardware/desktop.nix
    ../modules/common-desktop.nix
    ../modules/luks-tpm.nix
    ../modules/btrfs-maintenance.nix
  ];

  networking.hostName = "chris-desktop";

  # Skip the systemd-boot menu on boot.
  boot.loader.timeout = 0;

  # Desktop-specific kernel modules
  boot.kernelModules = [ "sg" ];

  # Hibernate is intentionally unused on the desktop (plain suspend only, see
  # home/desktop.nix), so no boot.resumeDevice / resume_offset here. zswap stays
  # as a compressed swap cache.
  boot.kernelParams = [
    "zswap.enabled=1"
  ];

  # AMD GPU configuration
  hardware.amdgpu = {
    initrd.enable = true;
  };

  # Rusticl OpenCL for radeonsi; ICD + env var both needed.
  # why: docs/notes.md#desktop
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

  # Sunshine streaming, from unstable (nixpkgs lags upstream badly).
  # why: docs/notes.md#desktop
  services.sunshine = {
    enable = true;
    package = pkgs-unstable.sunshine;
    autoStart = true;
    capSysAdmin = true;
    openFirewall = true;
  };

  # Keep Sunshine out of the GDM greeter session — it grabs the RTSP port
  # there otherwise. why: docs/notes.md#desktop
  systemd.user.services.sunshine.unitConfig.ConditionUser = "chris";

  # Feral GameMode — on-demand performance for games (opt-in per title).
  programs.gamemode.enable = true;

  # Wake-on-LAN on the wired NIC. Also enable "Power On by PCIE/LAN" (or
  # equivalent) in BIOS for wake from full power-off.
  networking.interfaces.eno1.wakeOnLan.enable = true;

  # Disable problematic PCIe wake sources. GPP0 is the NVMe root port (its PME
  # aborts every S3 sleep ~3 ms after entry) and GPP8 the GPU's. `/proc/acpi/
  # wakeup` is a *toggle*, so only write a device when it currently reads
  # *enabled: a blind `echo` re-armed both whenever a rebuild restarted this
  # unit (2026-11-07: sleep started waking again ~6 s after every suspend).
  # Check with `grep GPP0 /proc/acpi/wakeup` — it should say *disabled.
  systemd.services.disable-wake-sources = {
    description = "Disable PCIe wake sources (NVMe/GPU root ports)";
    wantedBy = [ "multi-user.target" ];
    after = [ "multi-user.target" ];
    script = ''
      for dev in GPP0 GPP8; do
        if grep -q "^$dev[[:space:]].*\*enabled" /proc/acpi/wakeup; then
          echo "$dev" > /proc/acpi/wakeup
        fi
      done
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

  # CoolerControl daemon and GUI for fan curve management
  programs.coolercontrol.enable = true;
}
