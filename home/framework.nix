{ config, pkgs, pkgs-unstable, ... }:

{
  imports = [
    ./common.nix
  ];

  # User identity
  home.username = "chris";
  home.homeDirectory = "/home/chris";

  # Framework-specific packages
  home.packages = with pkgs; [
    fwupd
    gearlever
    appimage-run
    moonlight-qt
    lm_sensors
    amdgpu_top

  ];

  # Framework-specific bash aliases
  programs.bash.shellAliases = {
    rebuild = "sudo nixos-rebuild switch --flake /home/chris/nix-config#chris-framework";
  };
}
