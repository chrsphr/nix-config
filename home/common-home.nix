{ config, lib, pkgs, pkgs-unstable, network, ... }:

{
  imports = [
    ./common-terminal.nix
  ];

  # Home Manager state version
  home.stateVersion = "26.05";

  # Shared GUI packages for both desktop and framework laptop
  home.packages = with pkgs; [
    pkgs-unstable.beeper
    ## pkgs-unstable.qgis
    qgis-ltr
    # nixpkgs 26.05's vscode 1.144 fails at patchPhase: it still expects
    # the pre-1.122 ripgrep path. Unstable has the fix. Revert once the
    # backport lands: https://github.com/NixOS/nixpkgs/pull/585147
    pkgs-unstable.vscode
    pkgs-unstable.claude-code
    spotify
    conda
    # ONE --enable-features list: Chromium keeps only the last occurrence of a
    # switch, so a second one silently drops the VA-API features. Both the old
    # (Vaapi*) and current (Accelerated*) feature names are listed.
    (pkgs.symlinkJoin {
      name = "teams-for-linux";
      paths = [ pkgs.teams-for-linux ];
      buildInputs = [ pkgs.makeWrapper ];
      postBuild = ''
        wrapProgram $out/bin/teams-for-linux \
          --add-flags "--enable-features=VaapiVideoDecoder,VaapiVideoEncoder,AcceleratedVideoDecodeLinuxGL,AcceleratedVideoEncoder,UseOzonePlatform,WaylandWindowDecorations --enable-gpu-rasterization --enable-native-gpu-memory-buffers --ozone-platform-hint=auto"
      '';
    })
    google-fonts
    nixos-generators
    drawio
    google-chrome
    (pkgs-unstable.darktable.override { withAi = true; })
    onnxruntime
    python3
    discord
    uv
    clinfo       # `clinfo` to verify OpenCL (Rusticl) GPU detection
    libva-utils  # `vainfo` to verify VA-API hardware video decode
    libreoffice-fresh
    resources

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
    "org/gnome/desktop/applications/terminal" = {
      exec = "ghostty";
      exec-arg = "";
    };
    "org/gnome/desktop/default-applications/terminal" = {
      exec = "ghostty";
      exec-arg = "";
    };
  };

  # SSH (desktop + Framework only). github.com pinned to the personal key.
  # history: docs/notes.md#ssh-identity-mixup
  programs.ssh = {
    enable = true;
    enableDefaultConfig = false;
    settings = (lib.mapAttrs' (name: cfg:
      lib.nameValuePair name {
        HostName = network.getIP name;
        User = cfg.sshUser;
      }) network.hosts) // {
      "github.com" = {
        IdentityFile = "~/.ssh/id_chrsphr.pub";
        IdentitiesOnly = "yes";
      };
      "*" = {
        IdentityAgent = "~/.1password/agent.sock";
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
