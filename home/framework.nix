{ config, pkgs, pkgs-unstable, inputs, ... }:
let
  noctalia-pkg = config.programs.noctalia-shell.package;
in

{
  imports = [
    ./common.nix
    inputs.noctalia.homeModules.default
  ];

  # User identity
  home.username = "chris";
  home.homeDirectory = "/home/chris";

  # Noctalia shell
  programs.noctalia-shell.enable = true;

  # Framework-specific packages
  home.packages = with pkgs; [
    fwupd
    gearlever
    appimage-run
    moonlight-qt
    lm_sensors
    amdgpu_top
    fuzzel
    brightnessctl
    kdePackages.polkit-kde-agent-1
  ];

  # Framework-specific bash aliases
  programs.bash.shellAliases = {
    rebuild = "sudo nixos-rebuild switch --flake /home/chris/nix-config#chris-framework";
  };

  # Foot terminal
  programs.foot = {
    enable = true;
    settings = {
      main = {
        font = "JetBrainsMono Nerd Font:size=11";
        pad = "8x8";
      };
      colors = {
        background = "1e1e2e";
        foreground = "cdd6f4";
      };
    };
  };

  # Niri compositor config (written as plain KDL config file)
  xdg.configFile."niri/config.kdl".text = ''
    // Input
    input {
      keyboard {
        xkb {
          layout "gb"
        }
      }
      touchpad {
        tap
        natural-scroll
      }
    }

    // Appearance
    prefer-no-csd

    layout {
      gaps 8
      border {
        width 2
        active-color "#89b4fa"
        inactive-color "#313244"
      }
    }

    // Start polkit agent on launch
    spawn-at-startup "${pkgs.kdePackages.polkit-kde-agent-1}/libexec/polkit-kde-authentication-agent-1"

    // Start noctalia shell
    spawn-at-startup "${noctalia-pkg}/bin/noctalia-shell"

    // Keybindings (Super = Mod)
    binds {
      Mod+Return { spawn "foot"; }
      Mod+D { spawn "fuzzel"; }
      Mod+Q { close-window; }
      Mod+Shift+E { quit skip-confirmation=true; }

      // Focus
      Mod+H { focus-column-left; }
      Mod+L { focus-column-right; }
      Mod+J { focus-window-down; }
      Mod+K { focus-window-up; }
      Mod+Left { focus-column-left; }
      Mod+Right { focus-column-right; }
      Mod+Down { focus-window-down; }
      Mod+Up { focus-window-up; }

      // Move
      Mod+Shift+H { move-column-left; }
      Mod+Shift+L { move-column-right; }
      Mod+Shift+J { move-window-down; }
      Mod+Shift+K { move-window-up; }
      Mod+Shift+Left { move-column-left; }
      Mod+Shift+Right { move-column-right; }

      // Workspaces
      Mod+1 { focus-workspace 1; }
      Mod+2 { focus-workspace 2; }
      Mod+3 { focus-workspace 3; }
      Mod+4 { focus-workspace 4; }
      Mod+5 { focus-workspace 5; }
      Mod+Shift+1 { move-column-to-workspace 1; }
      Mod+Shift+2 { move-column-to-workspace 2; }
      Mod+Shift+3 { move-column-to-workspace 3; }
      Mod+Shift+4 { move-column-to-workspace 4; }
      Mod+Shift+5 { move-column-to-workspace 5; }

      // Layout
      Mod+F { fullscreen-window; }

      // Volume
      XF86AudioRaiseVolume { spawn "wpctl" "set-volume" "@DEFAULT_AUDIO_SINK@" "5%+"; }
      XF86AudioLowerVolume { spawn "wpctl" "set-volume" "@DEFAULT_AUDIO_SINK@" "5%-"; }
      XF86AudioMute { spawn "wpctl" "set-mute" "@DEFAULT_AUDIO_SINK@" "toggle"; }

      // Brightness
      XF86MonBrightnessUp { spawn "brightnessctl" "set" "5%+"; }
      XF86MonBrightnessDown { spawn "brightnessctl" "set" "5%-"; }

      // Screenshot
      Print { screenshot; }
      Mod+Print { screenshot-window; }
      Mod+Shift+Print { screenshot-screen; }
    }
  '';
}
