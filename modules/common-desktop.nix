{ config, pkgs, pkgs-unstable ? pkgs, deploy-rs-pkg ? null, ... }:

let
  keys = import ./keys.nix;
in
{
  imports = [
    ./locale.nix
  ];

  # Disable documentation to speed up evaluation
  documentation.enable = false;

  # Nix configuration
  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 14d";
  };

  # Bootloader
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # Use latest kernel
  boot.kernelPackages = pkgs.linuxPackages_latest;

  # Plymouth boot splash — quiet kernel + initrd so the splash isn't preceded by text.
  boot.plymouth.enable = true;
  boot.consoleLogLevel = 0;
  boot.initrd.verbose = false;
  boot.kernelParams = [
    "quiet"
    "splash"
    "loglevel=3"
    "rd.systemd.show_status=auto"
    "rd.udev.log_level=3"
    "udev.log_priority=3"
    "vt.global_cursor_default=0"
  ];

  # Power management
  powerManagement.enable = true;

  # Networking
  networking.networkmanager.enable = true;

  # X11 and GNOME Desktop
  services.xserver.enable = true;
  services.displayManager.gdm.enable = true;
  services.desktopManager.gnome.enable = true;
  # Mutter experimental features removed — scale-monitor-framebuffer and
  # variable-refresh-rate are defaults in Mutter 50.

  # Keymap configuration
  services.xserver.xkb = {
    layout = "gb";
    variant = "";
  };
  console.keyMap = "uk";

  # Printing
  services.printing.enable = true;

  # Sound with PipeWire
  services.pulseaudio.enable = false;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
  };

  # Graphics
  hardware.graphics = {
    enable = true;
    enable32Bit = true;
  };

  # Bluetooth
  hardware.bluetooth = {
    enable = true;
    powerOnBoot = true;
    settings = {
      General = {
        Experimental = true;
        FastConnectable = true;
      };
      Policy = {
        AutoEnable = true;
      };
    };
  };

  # User account
  users.users.chris = {
    isNormalUser = true;
    shell = pkgs.zsh;
    openssh.authorizedKeys.keys = [ keys.chris ];
    description = "Chris";
    extraGroups = [ "networkmanager" "wheel" ];
  };

  # Programs
  programs.zsh.enable = true;  # Enable zsh system-wide
  programs.firefox.enable = true;
  programs.steam = {
    enable = true;
    remotePlay.openFirewall = true;
    dedicatedServer.openFirewall = true;
  };

  # 1Password
  programs._1password.enable = true;
  programs._1password-gui = {
    enable = true;
    polkitPolicyOwners = [ "chris" ];
  };

  # Services
  services.colord.enable = true;
  services.flatpak.enable = true;

  # Tailscale VPN
  services.tailscale = {
    enable = true;
    openFirewall = true;
    useRoutingFeatures = "client";  # Required for using exit nodes
    extraSetFlags = [ "--operator=chris" ];
  };

  # SSH server
  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "no";
      PasswordAuthentication = false;
    };
  };

  # Firewall
  networking.firewall = {
    allowedTCPPorts = [ 22 ];
    # Required for Tailscale exit nodes - return traffic comes via different interface
    checkReversePath = "loose";
  };

  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;

  # System packages
  environment.systemPackages = with pkgs; [
    vim
    htop
  ] ++ pkgs.lib.optional (deploy-rs-pkg != null) deploy-rs-pkg;

  # State version
  system.stateVersion = "26.05";
}
