{ config, pkgs, pkgs-unstable, ... }:

let
  # ChromaLeon (formerly "User Accent Colors"), extension id 10070. Not packaged
  # in nixpkgs, so build it from the extensions.gnome.org zip. Ships an
  # uncompiled gschema, so compile it during the build.
  chromaleon = pkgs.stdenvNoCC.mkDerivation {
    pname = "gnome-shell-extension-chromaleon";
    version = "35";
    src = pkgs.fetchzip {
      url = "https://extensions.gnome.org/download-extension/user-accent-colors@fabito02.shell-extension.zip?version_tag=72021";
      hash = "sha256-lLdB0f/NVhOY8mN4cj8KdWCN3yoVBp41yj9fTohv6SY=";
      stripRoot = false;
      extension = "zip";
    };
    nativeBuildInputs = [ pkgs.glib ];
    dontConfigure = true;
    dontBuild = true;
    installPhase = ''
      runHook preInstall
      d=$out/share/gnome-shell/extensions/user-accent-colors@fabito02
      mkdir -p $d
      cp -r * $d/
      glib-compile-schemas $d/schemas
      runHook postInstall
    '';
  };
in
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
    (pkgs-unstable.darktable.override { withAi = true; })
    onnxruntime
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
    chromaleon
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
        "user-accent-colors@fabito02"
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
