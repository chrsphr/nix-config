{ config, pkgs, pkgs-unstable, sops-nix, gb-grid, gb-grid-pkg, lib, ... }:

# minihutch (192.168.1.3): the second baremetal container host — compute
# only, no ZFS/NFS/backup. Runs beeper, caddy, pihole-2, tailscale, uptime.
# why: docs/notes.md#minihutch

let
  keys = import ../modules/keys.nix;
in
{
  imports = [
    ../modules/locale.nix
    # LAN bond/bridge + every container with `parent = "minihutch"`.
    ../modules/container-host.nix
    # Exports the USB TV tuner to hutch, where Plex consumes it.
    ../modules/usbip-tuner.nix
  ];

  # The tuner is plugged in here but belongs to hutch while exported.
  # why: docs/notes.md#minihutch
  usbipTuner.export = {
    enable = true;
    busid = "3-1";
    idVendor = "045e";
    idProduct = "02d5";
    # usbipd is unauthenticated; only hutch may claim the tuner.
    allowFrom = "192.168.1.2";
  };

  # No kernel pin (no ZFS here) — tracks the nixpkgs default, which must stay
  # equal to hutch's pin for USB/IP. why: docs/notes.md#kernel-pin
  networking.hostName = "minihutch";

  containerHost = {
    enable = true;

    # Onboard 1GbE MAC — fixed LAN identity for .3. WiFi is never enslaved
    # (bond matches Type=ether only). why: docs/notes.md#minihutch
    macAddress = "10:02:b5:86:02:0a";

    # Age keys placed by hand — docs/minihutch-install.md step 7.
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

  # SSH + deploy user for deploy-rs. Keys only — both options stated on
  # purpose. why: docs/notes.md#hutch
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
  # chris: interactive login. Same uid as on hutch; password set imperatively
  # on the box on purpose. why: docs/notes.md#hutch
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
