{ config, pkgs, pkgs-unstable, ... }:

{
  home.username = "chris";
  home.homeDirectory = "/home/chris";

  # Home Manager state version
  home.stateVersion = "25.11";

  # Dev-focused packages for WSL
  home.packages = with pkgs; [
    # Development tools
    git
    claude-code

    # Terminal utilities
    fastfetch
    btop
    dig
    wget
    jq
    ripgrep
    fd
    tree
    unzip
    socat      # For 1Password SSH agent bridge
    sshpass    # For SSH with passwords

    # Python with data science packages and virtualenv support
    (python3.withPackages (ps: with ps; [
      requests
      pandas
      matplotlib
      jupyter
      notebook
      virtualenv
    ]))

    # pyenv for managing multiple Python versions
    pyenv

    # Fonts for terminal
    nerd-fonts.fira-code
    nerd-fonts.meslo-lg
  ];

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
      rebuild-wsl = "sudo nixos-rebuild switch --flake /home/chris/nix-config#chris-wsl";
      rebuild-framework = "sudo nixos-rebuild switch --flake /home/chris/nix-config#chris-framework";
      rebuild-desktop = "sudo nixos-rebuild switch --flake /home/chris/nix-config#chris-desktop";
      code = "/mnt/c/Users/Chris.McNeill/AppData/Local/Programs/Microsoft\\ VS\\ Code/bin/code";
    };

    initContent = ''
      export PYENV_ROOT="$HOME/.pyenv"
      export PATH="$PYENV_ROOT/bin:$PATH"
      eval "$(pyenv init -)"

      # 1Password SSH agent via Windows bridge
      export SSH_AUTH_SOCK="$HOME/.ssh/agent.sock"
    '';

    oh-my-zsh = {
      enable = true;
      theme = "robbyrussell";
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

  # 1Password SSH agent bridge (connects Windows SSH agent to WSL)
  home.activation.downloadNpiperelay = config.lib.dag.entryAfter ["writeBoundary"] ''
    if [ ! -f "$HOME/.local/bin/npiperelay.exe" ]; then
      $DRY_RUN_CMD mkdir -p "$HOME/.local/bin"
      $DRY_RUN_CMD ${pkgs.curl}/bin/curl -L -o /tmp/npiperelay.zip \
        https://github.com/jstarks/npiperelay/releases/latest/download/npiperelay_windows_amd64.zip
      $DRY_RUN_CMD ${pkgs.unzip}/bin/unzip -o /tmp/npiperelay.zip -d "$HOME/.local/bin/"
      $DRY_RUN_CMD rm -f /tmp/npiperelay.zip
      echo "Downloaded npiperelay to $HOME/.local/bin/npiperelay.exe"
    fi
  '';

  # Systemd service to bridge 1Password SSH agent from Windows
  systemd.user.services.ssh-agent-bridge = {
    Unit = {
      Description = "1Password SSH Agent Bridge (Windows to WSL)";
      After = [ "network.target" ];
    };
    Service = {
      Type = "simple";
      ExecStartPre = "${pkgs.coreutils}/bin/rm -f %h/.ssh/agent.sock";
      ExecStart = "${pkgs.socat}/bin/socat UNIX-LISTEN:%h/.ssh/agent.sock,fork EXEC:'%h/.local/bin/npiperelay.exe -ei -ep -s //./pipe/openssh-ssh-agent',nofork";
      Restart = "on-failure";
      RestartSec = "5s";
    };
    Install = {
      WantedBy = [ "default.target" ];
    };
  };

  # Allow Home Manager to manage itself
  programs.home-manager.enable = true;
}
