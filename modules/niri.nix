{ config, pkgs, ... }:

{
  # Niri scrollable-tiling Wayland compositor.
  # Automatically registers the Niri Wayland session with GDM,
  # configures xdg-desktop-portal (gnome/gtk), and enables gnome-keyring.
  programs.niri.enable = true;

  # Hyprlock PAM authentication support (required for unlocking)
  programs.hyprlock.enable = true;

  # System-wide utilities for Wayland desktop integration
  environment.systemPackages = with pkgs; [
    brightnessctl
    playerctl
    wl-clipboard
    libnotify
  ];
}
