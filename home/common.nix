{ config, pkgs, pkgs-unstable, ... }:

{
  # Home Manager state version
  home.stateVersion = "25.11";

  # Shared packages for both desktop and framework laptop
  home.packages = with pkgs; [
    pkgs-unstable.beeper
    pkgs-unstable.qgis
    git
    vscode
    spotify
    conda
    fastfetch
    dig
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
    wget
    google-chrome
    btop
    pkgs-unstable.darktable
    pkgs-unstable.claude-code
    discord
    uv
    amdgpu_top
    libreoffice-fresh

    # Terminal utilities for oh-my-zsh
    nerd-fonts.fira-code
    nerd-fonts.meslo-lg

    # GNOME Extensions
    gnomeExtensions.blur-my-shell
    gnomeExtensions.emoji-copy
    gnomeExtensions.appindicator

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
      ];
    };
    "org/gnome/desktop/interface" = {
      color-scheme = "prefer-dark";
      gtk-theme = "Adwaita-dark";
      icon-theme = "Adwaita";
      cursor-theme = "Adwaita";
    };
  };

  # Git configuration
  programs.git = {
    enable = true;
    settings = {
      user = {
        name = "chrsphr";
        email = "chris@mcneill.fyi";
      };
      init.defaultBranch = "main";
      pull.rebase = false;
    };
  };

  # Zsh with oh-my-zsh
  programs.zsh = {
    enable = true;
    enableCompletion = true;
    autosuggestion.enable = true;
    syntaxHighlighting.enable = true;

    shellAliases = {
      ll = "ls -la";
      rebuild-framework = "sudo nixos-rebuild switch --flake /home/chris/nix-config#chris-framework";
      rebuild-desktop = "sudo nixos-rebuild switch --flake /home/chris/nix-config#chris-desktop";
    };

    oh-my-zsh = {
      enable = true;
      theme = "robbyrussell";  # Classic theme, or try: "agnoster", "powerlevel10k/powerlevel10k"
      plugins = [
        "git"
        "sudo"
        "docker"
        "kubectl"
        "colored-man-pages"
        "command-not-found"
      ];
    };
  };

  # Allow Home Manager to manage itself
  programs.home-manager.enable = true;
}
