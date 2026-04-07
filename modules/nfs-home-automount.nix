{ config, pkgs, lib, ... }:

# Mounts the home NAS over NFS when on the home WiFi network or when
# Tailscale is connected. Unmounts when neither condition is true.
# Designed for portable devices that roam between networks.

let
  nas = "192.168.1.12";
  mountPoint = "/mnt/Media";
  nasExport = "${nas}:/mnt/Hutch/Media";
  homeSSID = "Rebel Hideout";
  vpnInterface = "tailscale0";

  dispatcherScript = pkgs.writeShellScript "nfs-home-automount" ''
    INTERFACE="$1"
    ACTION="$2"

    is_home_wifi() {
      SSID=$(${pkgs.networkmanager}/bin/nmcli -t -f active,ssid dev wifi 2>/dev/null \
        | grep '^yes:' | cut -d: -f2)
      [ "$SSID" = "${homeSSID}" ]
    }

    is_vpn_up() {
      ${pkgs.iproute2}/bin/ip link show "${vpnInterface}" 2>/dev/null | grep -q "state UP"
    }

    should_mount() {
      is_home_wifi || is_vpn_up
    }

    do_mount() {
      if ! ${pkgs.util-linux}/bin/mountpoint -q "${mountPoint}"; then
        mount "${mountPoint}" && logger "nfs-home-automount: mounted ${mountPoint}"
      fi
    }

    do_umount() {
      if ${pkgs.util-linux}/bin/mountpoint -q "${mountPoint}"; then
        umount -l "${mountPoint}" && logger "nfs-home-automount: unmounted ${mountPoint}"
      fi
    }

    case "$ACTION" in
      up|vpn-up|connectivity-change)
        if should_mount; then
          do_mount
        fi
        ;;
      down|vpn-down)
        if ! should_mount; then
          do_umount
        fi
        ;;
    esac
  '';
in
{
  boot.supportedFilesystems = [ "nfs" ];
  services.rpcbind.enable = true;

  # fstab entry: noauto so nothing mounts it automatically.
  # No x-systemd.automount so file managers cannot trigger it.
  fileSystems."${mountPoint}" = {
    device = nasExport;
    fsType = "nfs";
    options = [
      "noauto"
      "nofail"
      "_netdev"
      "soft"
      "timeo=30"
      "retrans=2"
      "bg"
    ];
  };

  # NetworkManager dispatcher: mount/unmount based on network state
  networking.networkmanager.dispatcherScripts = [{
    source = dispatcherScript;
    type = "basic";
  }];
}
