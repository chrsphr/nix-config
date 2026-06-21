{ config, pkgs, pkgs-unstable, ... }:

{
  imports = [
    ./common-home.nix
  ];

  # User identity
  home.username = "chris";
  home.homeDirectory = "/home/chris";

  # Framework-specific packages
  home.packages = with pkgs; [
    gearlever
    appimage-run
    moonlight-qt
    lm_sensors
    trayscale  # Tailscale GUI tray app
  ];

  # Framework-specific bash aliases
  programs.bash.shellAliases = {
    rebuild = "sudo nixos-rebuild switch --flake /home/chris/nix-config#chris-framework";
  };

  # Disable GNOME's ambient auto-brightness so the backlight is fully manual
  # (it was reacting choppily to the panel ALS).
  dconf.settings."org/gnome/settings-daemon/plugins/power".ambient-enabled = false;
}
