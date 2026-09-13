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
    gnome-boxes
    gamescope
    vulkan-tools
    lsscsi
    docker-compose
    makemkv
    sysstat
    handbrake
    filebot
    pkgs-unstable.claude-code

  ];

  # Desktop-specific bash aliases
  programs.bash.shellAliases = {
    rebuild = "sudo nixos-rebuild switch --flake /home/chris/nix-config#chris-desktop";
  };

  # Sleep after 15 min idle on AC; plain suspend only (no hibernate on desktop).
  dconf.settings."org/gnome/settings-daemon/plugins/power" = {
    sleep-inactive-ac-type = "suspend";
    sleep-inactive-ac-timeout = 900;
  };
}
