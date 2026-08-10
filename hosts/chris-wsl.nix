{ config, pkgs, ... }:

let
  keys = import ../modules/keys.nix;
in
{
  imports = [
    ../modules/locale.nix
  ];

  # WSL-specific configuration
  wsl = {
    enable = true;
    defaultUser = "chris";
    startMenuLaunchers = true;
    wslConf.automount.root = "/mnt";
    wslConf.interop.appendWindowsPath = false;
    interop.register = true;
  };

  # No interactive docs needed in WSL; trims closure size (same rationale as common-desktop.nix).
  documentation.enable = false;

  # Nix configuration
  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 14d";
  };

  # Networking
  networking.hostName = "chris-wsl";

  # User account
  users.users.chris = {
    isNormalUser = true;
    shell = pkgs.zsh;
    openssh.authorizedKeys.keys = [ keys.chris ];
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
  system.stateVersion = "26.05";
}
