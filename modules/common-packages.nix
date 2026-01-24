{ pkgs, pkgs-unstable ? pkgs, ... }:

{
  # Shared packages for both desktop and framework laptop
  sharedPackages = with pkgs; [
    beeper
    qgis
    git
    vscode
    spotify
    conda
    fastfetch
    dig
    teams-for-linux
    google-fonts
    nixos-generators
    drawio
    wget
    google-chrome
    btop
    pkgs-unstable.darktable
    claude-code
    amdgpu_top

  ];
}
