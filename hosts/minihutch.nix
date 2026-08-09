{ config, pkgs, pkgs-unstable, sops-nix, gb-grid, gb-grid-pkg, lib, ... }:

# minihutch (192.168.1.3): the second baremetal container host.
#
# Same shape as hutch — modules/container-host.nix gives it the bond/bridge
# and one systemd-nspawn container per lib/network.nix host with
# `parent = "minihutch"` — but compute only: no ZFS pool, no NFS, no B2
# backup, so no modules/nas.nix and no media bind mounts.
#
# Runs: beeper, caddy, pihole-2, tailscale, uptime (moved off hutch
# 2026-08-09). Deploying minihutch deploys all five.

let
  keys = import ../modules/keys.nix;
in
{
  imports = [
    ../modules/locale.nix
    # LAN bond/bridge + every container with `parent = "minihutch"`, plus the
    # btrfs container-root snapshots that come with it.
    ../modules/container-host.nix
    # Exports the USB TV tuner to hutch, where Plex consumes it.
    ../modules/usbip-tuner.nix
  ];

  # The Xbox One Digital TV Tuner is plugged into this box, but Plex runs on
  # hutch. Export it over USB/IP; hutch attaches it (see hosts/hutch.nix).
  # Binding it here hands the device to hutch entirely — minihutch's own
  # /dev/dvb goes away, which is fine as nothing local uses it.
  usbipTuner.export = {
    enable = true;
    busid = "3-1";
    idVendor = "045e";
    idProduct = "02d5";
    # usbipd is unauthenticated; only hutch may claim the tuner.
    allowFrom = "192.168.1.2";
  };

  # No kernel pin: hutch is held at 6.18 by ZFS 2.4.3's max supported version,
  # and minihutch has no ZFS, so it tracks the nixpkgs default.
  networking.hostName = "minihutch";

  containerHost = {
    enable = true;

    # The onboard 1GbE port (enp2s0, igc driver), read off the live ISO
    # 2026-08-09. Fixes .3's LAN identity so it survives boots and cable
    # moves. The box also has WiFi (wlp1s0, rtw89) — systemd matches the bond
    # slaves on Type=ether, and WiFi is Type=wlan, so it is never enslaved.
    macAddress = "10:02:b5:86:02:0a";

    # Both decrypt with a copy of the *laptop* age key at
    # /var/lib/sops-nix/<name>/keys.txt, which is NOT in the repo and must be
    # placed by hand on this box — see docs/minihutch-install.md step 7.
    # (caddy has its own per-container key; uptime uses the laptop key.)
    withSecrets = [ "caddy" "uptime" ];

    perContainer = {
      # /dev/net/tun + CAP_NET_ADMIN for tailscaled.
      tailscale.enableTun = true;
    };
  };

  # Boot loader
  boot.loader = {
    systemd-boot.enable = true;
    efi.canTouchEfiVariables = true;
  };

  # SSH + deploy user for deploy-rs. Keys only: PasswordAuthentication off,
  # and KbdInteractiveAuthentication off too — with UsePAM the latter would
  # otherwise *advertise* a keyboard-interactive path (blocked only by
  # pam_deny in the sshd PAM stack). Stating both makes keys-only unambiguous.
  services.openssh = {
    enable = true;
    openFirewall = true;
    settings = {
      PermitRootLogin = "no";
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
    };
  };
  users.users.deploy = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    openssh.authorizedKeys.keys = [ keys.chris ];
  };
  # chris: interactive console/SSH login. Same uid as on hutch so the two
  # boxes agree over NFS/rsync. Password is set once on the live box with
  # chpasswd (survives rebuilds, keeps the secret out of the repo); add
  # initialHashedPassword if that ever needs to be declarative.
  users.users.chris = {
    isNormalUser = true;
    uid = 1001;
    extraGroups = [ "wheel" ];
    openssh.authorizedKeys.keys = [ keys.chris ];
  };
  users.users.root.openssh.authorizedKeys.keys = [ keys.chris ];
  security.sudo.wheelNeedsPassword = false;

  # Nix settings
  nix.settings = {
    experimental-features = [ "nix-command" "flakes" ];
    sandbox = false;
    require-sigs = false;
  };

  environment.systemPackages = with pkgs; [
    vim
    htop
    git
  ];

  nixpkgs.config.allowUnfree = true;
  system.stateVersion = "26.05";
}
