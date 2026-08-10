{ config, pkgs, pkgs-unstable, ... }:

{
  imports = [
    ./common-terminal.nix
  ];

  home.username = "chris";
  home.homeDirectory = "/home/chris";

  # Set default browser to wsl-open so commands like `az login` open in Windows browser
  home.sessionVariables = {
    BROWSER = "wsl-open";
  };

  # Home Manager state version
  home.stateVersion = "26.05";

  # Dev-focused packages for WSL
  home.packages = with pkgs; [
    # Development tools
    pkgs-unstable.azure-cli
    terraform

    # Terminal utilities
    jq
    ripgrep
    fd
    tree
    unzip
    socat      # For 1Password SSH agent bridge
    sshpass    # For SSH with passwords
    pkgs-unstable.github-copilot-cli
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
    xdg-utils
    wsl-open
  ];

  # WSL-specific shell aliases and init settings (merged with common-terminal)
  programs.zsh = {
    shellAliases = {
      rebuild-wsl = "sudo nixos-rebuild switch --flake /home/chris/nix-config#chris-wsl";
      code = "/mnt/c/Users/Chris.McNeill/AppData/Local/Programs/Microsoft\\ VS\\ Code/bin/code";
    };

    initContent = ''
      export PYENV_ROOT="$HOME/.pyenv"
      export PATH="$PYENV_ROOT/bin:$PATH"
      eval "$(pyenv init -)"

      # 1Password SSH agent via Windows bridge
      export SSH_AUTH_SOCK="$HOME/.ssh/agent.sock"
    '';
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
