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
  ];

  # No kernel pin: hutch is held at 6.18 by ZFS 2.4.3's max supported version,
  # and minihutch has no ZFS, so it tracks the nixpkgs default.
  networking.hostName = "minihutch";

  containerHost = {
    enable = true;

    # ⚠ TODO before/at first boot: set this to this box's onboard NIC MAC
    # (`ip -br link` on the live ISO, the physical port you'll cable). While
    # it is null, bond0 adopts whichever port MAC it likes and br0 can inherit
    # a *container veth's* random MAC when a container restarts — meaning
    # .3's LAN identity (DHCP reservations, UniFi client entry, ARP) can
    # change out from under you. Fine for the install, not for steady state.
    macAddress = null;

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
