{ pkgs, ... }:

# Base shared by the two baremetal servers (hutch, minihutch): boot loader,
# keys-only SSH, the deploy/chris accounts, telemetry and Nix settings.
# Anything role- or machine-specific stays in the role modules or
# hosts/<name>.nix.

let
  keys = import ./keys.nix;
in
{
  imports = [
    ./locale.nix
    # Newest ZFS-compatible kernel. Shared so the fleet runs one kernel even
    # though only hutch has ZFS.
    ./kernel-pin.nix
    # Ship the journal to the prometheus container.
    ./journal-upload.nix
  ];

  boot.loader = {
    systemd-boot.enable = true;
    # Cap boot entries: the 512M ESP holds ~9 kernel+initrd pairs, and no
    # nix.gc runs here, so generations would otherwise fill /boot and every
    # deploy would die copying the new kernel before the builder prunes.
    systemd-boot.configurationLimit = 5;
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
  # chris: interactive login. uid fixed and identical on both hosts; password
  # set imperatively on the box on purpose. why: docs/notes.md#hutch
  users.users.chris = {
    isNormalUser = true;
    uid = 1001;
    extraGroups = [ "wheel" ];
    openssh.authorizedKeys.keys = [ keys.chris ];
  };
  users.users.root.openssh.authorizedKeys.keys = [ keys.chris ];
  security.sudo.wheelNeedsPassword = false;

  # Glances system telemetry web API (consumed by Homepage dashboard)
  services.glances = {
    enable = true;
    openFirewall = true;
  };

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
}
