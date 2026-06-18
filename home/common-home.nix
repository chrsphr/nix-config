{ config, pkgs, pkgs-unstable, ... }:

{
  imports = [
    ./common-terminal.nix
  ];

  # Home Manager state version
  home.stateVersion = "26.05";

  # Shared GUI packages for both desktop and framework laptop
  home.packages = with pkgs; [
    pkgs-unstable.beeper
    pkgs-unstable.qgis
    vscode
    spotify
    conda
    (pkgs.symlinkJoin {
      name = "teams-for-linux";
      paths = [ pkgs.teams-for-linux ];
      buildInputs = [ pkgs.makeWrapper ];
      postBuild = ''
        wrapProgram $out/bin/teams-for-linux \
          --add-flags "--enable-features=VaapiVideoDecoder,VaapiVideoEncoder --enable-gpu-rasterization --enable-native-gpu-memory-buffers --enable-features=UseOzonePlatform --ozone-platform-hint=auto"
      '';
    })
    google-fonts
    nixos-generators
    drawio
    google-chrome
    pkgs-unstable.darktable
    python3
    pkgs-unstable.gemini-cli
    pkgs-unstable.antigravity
    gh
    discord
    uv
    amdgpu_top
    libva-utils  # `vainfo` to verify VA-API hardware video decode
    libreoffice-fresh

    # GNOME Extensions
    gnomeExtensions.blur-my-shell
    gnomeExtensions.emoji-copy
    gnomeExtensions.appindicator
    gnomeExtensions.battery-time
  ];

  # Start 1Password minimised at login
  xdg.configFile."autostart/1password.desktop".text = ''
    [Desktop Entry]
    Name=1Password
    Exec=1password --silent %U
    Terminal=false
    Type=Application
    Icon=1password
    StartupWMClass=1Password
    X-GNOME-Autostart-enabled=true
  '';

  # GTK theme configuration
  gtk = {
    enable = true;
    theme = {
      name = "Adwaita-dark";
      package = pkgs.gnome-themes-extra;
    };
    iconTheme = {
      name = "Adwaita";
      package = pkgs.adwaita-icon-theme;
    };
    cursorTheme = {
      name = "Adwaita";
      package = pkgs.adwaita-icon-theme;
    };
    gtk3.extraConfig = {
      gtk-application-prefer-dark-theme = true;
    };
    gtk4.extraConfig = {
      gtk-application-prefer-dark-theme = true;
    };
  };

  # GNOME Extensions configuration
  dconf.settings = {
    "org/gnome/shell" = {
      disable-user-extensions = false;
      enabled-extensions = [
        "blur-my-shell@aunetx"
        "emoji-copy@felipeftn"
        "appindicatorsupport@rgcjonas.gmail.com"
        "batime@martin.zurowietz.de"
      ];
    };
    "org/gnome/desktop/interface" = {
      color-scheme = "prefer-dark";
      gtk-theme = "Adwaita-dark";
      icon-theme = "Adwaita";
      cursor-theme = "Adwaita";
    };
  };

  # SSH (desktop + Framework only — WSL bridges 1Password differently and is
  # left untouched). The 1Password agent holds both personal and work keys and
  # offered the work one first, which can't push to chrsphr repos. Pin github.com
  # to the personal (chrsphr) key; identitiesOnly + the public key on disk make
  # the agent use only that identity.
  programs.ssh = {
    enable = true;
    enableDefaultConfig = false;
    matchBlocks = {
      "github.com" = {
        identityFile = "~/.ssh/id_chrsphr.pub";
        identitiesOnly = true;
      };
      "*" = {
        identityAgent = "~/.1password/agent.sock";
      };
    };
  };

  # Personal GitHub public key, referenced by the github.com match block above.
  home.file.".ssh/id_chrsphr.pub".text = ''
    ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIO5Kox0nkeljrafIlbuwRKOp+om+ocvpuGOGBBfGyIia GitHub
  '';

  # Allow Home Manager to manage itself
  programs.home-manager.enable = true;
}
