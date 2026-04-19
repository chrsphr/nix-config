{ config, pkgs, lib, ... }:

let
  hostsLib = import ./hosts.nix { inherit lib; };
in
{
  imports = [
    ./hardware/pi-top.nix
  ];

  system.stateVersion = "25.11";

  # Boot - Pi 4 uses extlinux
  boot.loader.grub.enable = false;
  boot.loader.generic-extlinux-compatible.enable = true;
  boot.loader.timeout = 0;

  # Direct boot - copy kernel/initrd/dtbs to firmware partition on each activation
  system.activationScripts.piFirmwareBoot = let
    extlinuxConf = "/boot/extlinux/extlinux.conf";
    awk = "${pkgs.gawk}/bin/awk";
  in ''
    if [ -d /boot/firmware ]; then
      KERNEL=$(${awk} '/^\s*LINUX / {sub(/.*\.\.\//, ""); print; exit}' ${extlinuxConf})
      INITRD=$(${awk} '/^\s*INITRD / {sub(/.*\.\.\//, ""); print; exit}' ${extlinuxConf})
      CMDLINE=$(${awk} '/^\s*APPEND / {sub(/^\s*APPEND /, ""); print; exit}' ${extlinuxConf})
      FDTDIR=$(${awk} '/^\s*FDTDIR / {sub(/.*\.\.\//, ""); print; exit}' ${extlinuxConf})

      cp /boot/$KERNEL /boot/firmware/nixos-kernel
      cp /boot/$INITRD /boot/firmware/nixos-initrd
      rm -rf /boot/firmware/nixos-dtbs
      mkdir -p /boot/firmware/nixos-dtbs
      cp /boot/$FDTDIR/broadcom/bcm2711*.dtb /boot/firmware/nixos-dtbs/
      echo "$CMDLINE" > /boot/firmware/cmdline.txt
    fi
  '';

  # Networking
  networking = hostsLib.mkStaticNetwork "pi-top" // {
    hostName = "pi-top";
    firewall = {
      enable = true;
      allowedTCPPorts = [ 22 ];
    };
  };

  # Nix settings
  nix.settings = {
    experimental-features = [ "nix-command" "flakes" ];
  };

  nix.optimise.automatic = true;

  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 7d";
  };

  # SSH
  services.openssh = {
    enable = true;
    openFirewall = true;
    settings = {
      PermitRootLogin = "no";
      PasswordAuthentication = false;
    };
  };

  # Moonlight kiosk - launch directly via EGLFS (no compositor)
  systemd.services.moonlight = {
    description = "Moonlight Streaming";
    wantedBy = [ "multi-user.target" ];
    after = [ "systemd-logind.service" "bluetooth.service" "systemd-udev-settle.service" ];
    wants = [ "systemd-udev-settle.service" ];
    serviceConfig = {
      User = "moonlight";
      Environment = [
        "QT_QPA_PLATFORM=eglfs"
        "QT_QPA_EGLFS_INTEGRATION=eglfs_kms"
        "QT_QPA_EGLFS_KMS_ATOMIC=1"
        "QT_QPA_EGLFS_KMS_CONFIG=/etc/moonlight-kms.json"
        "XDG_RUNTIME_DIR=/run/user/1001"
      ];
      ExecStartPre = "${pkgs.coreutils}/bin/sleep 2";
      ExecStart = "${pkgs.moonlight-qt}/bin/moonlight";
      Restart = "always";
      RestartSec = 5;
      TTYPath = "/dev/tty1";
      StandardInput = "tty";
      StandardOutput = "journal";
      StandardError = "journal";
    };
  };

  # Moonlight user
  users.users.moonlight = {
    isNormalUser = true;
    extraGroups = [ "video" "render" "input" "tty" ];
  };

  # Point EGLFS at the vc4 card (card1 = HDMI, card0 = v3d render-only)
  environment.etc."moonlight-kms.json".text = builtins.toJSON {
    device = "/dev/dri/card1";
  };

  # GPU - enable KMS via device tree overlay
  hardware.raspberry-pi."4".fkms-3d.enable = true;
  boot.kernelModules = [ "vc4" "v3d" ];
  boot.blacklistedKernelModules = [ "simpledrm" ];
  hardware.graphics.enable = true;

  # Deploy user
  users.users.deploy = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIK1z+ixouoLpNHXciINsW1Jlvcmnr9E2ekFXCvvjBxfh"
    ];
  };

  users.users.root.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIK1z+ixouoLpNHXciINsW1Jlvcmnr9E2ekFXCvvjBxfh"
  ];

  security.sudo.wheelNeedsPassword = false;

  # Basic packages
  environment.systemPackages = with pkgs; [
    vim
    wget
    curl
    git
    htop
    bluez
    ubootTools
  ];

  # Bluetooth
  hardware.bluetooth.enable = true;
  hardware.bluetooth.powerOnBoot = true;
  hardware.raspberry-pi."4".bluetooth.enable = true;
  hardware.firmware = [ pkgs.raspberrypiWirelessFirmware ];

  # Timezone and locale
  time.timeZone = "Europe/London";
  i18n.defaultLocale = "en_GB.UTF-8";

  nixpkgs.config.allowUnfree = true;
}
