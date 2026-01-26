{ config, pkgs, ... }:

{
  # WSL-specific configuration
  wsl = {
    enable = true;
    defaultUser = "chris";
    startMenuLaunchers = true;
    wslConf.automount.root = "/mnt";
    wslConf.interop.appendWindowsPath = false;
  };

  # Nix configuration
  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 14d";
  };

  # Networking
  networking.hostName = "chris-wsl";

  # Localization
  time.timeZone = "Europe/London";
  i18n.defaultLocale = "en_GB.UTF-8";
  i18n.extraLocaleSettings = {
    LC_ADDRESS = "en_GB.UTF-8";
    LC_IDENTIFICATION = "en_GB.UTF-8";
    LC_MEASUREMENT = "en_GB.UTF-8";
    LC_MONETARY = "en_GB.UTF-8";
    LC_NAME = "en_GB.UTF-8";
    LC_NUMERIC = "en_GB.UTF-8";
    LC_PAPER = "en_GB.UTF-8";
    LC_TELEPHONE = "en_GB.UTF-8";
    LC_TIME = "en_GB.UTF-8";
  };

  # User account
  users.users.chris = {
    isNormalUser = true;
    shell = pkgs.zsh;
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIK1z+ixouoLpNHXciINsW1Jlvcmnr9E9ekFXCvvjBxfh"
    ];
    description = "Chris";
    extraGroups = [ "wheel" "docker" ];
  };

  # Programs
  programs.zsh.enable = true;

  # Enable nix-ld for running dynamically linked executables (needed for VSCode Server)
  programs.nix-ld.enable = true;
  programs.nix-ld.libraries = with pkgs; [
    # Add common libraries that VSCode Server might need
    stdenv.cc.cc
    zlib
    openssl
  ];

  # Docker for development
  virtualisation.docker.enable = true;

  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;

  # System packages
  environment.systemPackages = with pkgs; [
    vim
    htop
    git
    wget
    curl
  ];

  # State version
  system.stateVersion = "25.11";
}
