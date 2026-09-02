{ config, pkgs, pkgs-unstable, mcp-nixos-pkg, ... }:

{
  # Shared terminal packages for both desktop and WSL
  home.packages = with pkgs; [
    git
    fastfetch
    btop
    dig
    wget
    mcp-nixos-pkg  # MCP server for NixOS/Home Manager search (registered with Claude Code via `claude mcp add`)
    pkgs._1password-cli
    # Fonts for Oh-My-Zsh / terminals
    nerd-fonts.fira-code
    nerd-fonts.meslo-lg
    nerd-fonts.jetbrains-mono
    gh
    pkgs-unstable.opencode
  ];

  # Ghostty terminal (installs pkgs-unstable.ghostty)
  programs.ghostty = {
    enable = true;
    package = pkgs-unstable.ghostty;
    enableZshIntegration = true;
    settings = {
      theme = "Adwaita Dark";
      font-family = "JetBrainsMono Nerd Font Mono";
      # Touchpad (precision) scroll was too fast at the default of 1; halve it.
      mouse-scroll-multiplier = "precision:0.3,discrete:3";
      # Right-click pastes instead of opening the context menu.
      right-click-action = "paste";
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
}
