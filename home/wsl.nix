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
    vscode
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
    };

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

  # Allow Home Manager to manage itself
  programs.home-manager.enable = true;
}
