{ config, pkgs, pkgs-unstable, ... }:

{
  imports = [
    ./common-home.nix
  ];

  # User identity
  home.username = "chris";
  home.homeDirectory = "/home/chris";

  # Desktop-specific packages
  home.packages = with pkgs; [
    powertop
    fprintd
    gnome-boxes
    gamescope
    vulkan-tools
    lsscsi
    docker-compose
    makemkv
    sysstat
    handbrake
    filebot
  ];

  # Desktop-specific bash aliases
  programs.bash.shellAliases = {
    rebuild = "sudo nixos-rebuild switch --flake /home/chris/nix-config#chris-desktop";
  };
}
