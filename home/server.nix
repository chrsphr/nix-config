# Home-manager profile for headless servers.
#
# Deliberately self-contained instead of importing common-terminal.nix:
# that profile pulls Ghostty, desktop fonts, and the opencode CLI, none of
# which belong on a VPS. The git/zsh settings mirror the shared terminal
# profile.
{ pkgs, ... }:

{
  home.username = "chris";
  home.homeDirectory = "/home/chris";
  home.stateVersion = "26.05";

  home.packages = with pkgs; [
    git
    fastfetch
    btop
    dig
    wget
    gh
    jq
    curl
    htop
    vim
    tmux
    ripgrep
    fd
    tree
    unzip
  ];

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

  programs.zsh = {
    enable = true;
    enableCompletion = true;
    autosuggestion.enable = true;
    syntaxHighlighting.enable = true;

    shellAliases = {
      ll = "ls -la";
      rebuild-cloudhutch = "sudo nixos-rebuild switch --flake /home/chris/nix-config#cloudhutch";
    };

    oh-my-zsh = {
      enable = true;
      theme = "robbyrussell";
      plugins = [
        "git"
        "sudo"
        "colored-man-pages"
        "command-not-found"
      ];
    };
  };

  programs.home-manager.enable = true;
}
