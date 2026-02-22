{ config, pkgs, pkgs-unstable ? pkgs, ... }:

{
  imports = [
    ./hardware/framework.nix
    ./modules/common.nix
    ./modules/keyboard-backlight-timeout.nix
    ./modules/nfs-home-automount.nix
  ];

  # Sops secrets for WireGuard private key
  sops = {
    defaultSopsFile = ./secrets/wireguard.yaml;
    age.keyFile = "/home/chris/.config/sops/age/keys.txt";
    secrets.wireguard_private_key = {};
    templates."wg-home.nmconnection" = {
      mode = "0600";
      content = ''
        [connection]
        id=wg-home
        type=wireguard
        interface-name=wg-home
        autoconnect=false

        [wireguard]
        private-key=${config.sops.placeholder.wireguard_private_key}

        [wireguard-peer.xfd+GKSDFNUXN/07/JjHZKTM8In/R0wyH12i3ATuYH8=]
        endpoint=193.237.155.17:51820
        allowed-ips=0.0.0.0/0

        [ipv4]
        address1=192.168.13.5/32
        dns=192.168.13.1;
        method=manual

        [ipv6]
        method=ignore
        addr-gen-mode=default
      '';
    };
  };

  # Install WireGuard NM profile so it appears in GNOME VPN toggle
  # Sops secrets are installed via activation script before systemd services start
  systemd.services.nm-ensure-wireguard = {
    description = "Install WireGuard NetworkManager profile";
    wantedBy = [ "multi-user.target" ];
    after = [ "NetworkManager.service" ];
    serviceConfig.Type = "oneshot";
    serviceConfig.RemainAfterExit = true;
    script = ''
      install -m 0600 -o root -g root \
        ${config.sops.templates."wg-home.nmconnection".path} \
        /etc/NetworkManager/system-connections/wg-home.nmconnection
      ${pkgs.networkmanager}/bin/nmcli connection reload || true
    '';
  };

  # Hostname
  networking.hostName = "chris-framework";

  # AMD AI 300 specific kernel parameters
  boot.kernelParams = [
    "mem_sleep_default=s2idle"
    "nvme_core.default_ps_max_latency_us=5500"
    "amdgpu.ppfeaturemask=0xffffffff"
  ];

  # AMD GPU / OpenCL
  hardware.amdgpu.opencl.enable = true;

  # Bluetooth firmware and driver support
  hardware.enableRedistributableFirmware = true;
  hardware.firmware = with pkgs; [ linux-firmware ];
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
}
