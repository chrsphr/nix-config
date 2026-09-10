{ config, pkgs, ... }:

let
  polkitAgent = "${pkgs.kdePackages.polkit-kde-agent-1}/libexec/polkit-kde-authentication-agent-1";
in
{
  home.packages = with pkgs; [
    walker
    elephant
    libqalculate
    fuzzel
    kdePackages.polkit-kde-agent-1
    nerd-fonts.caskaydia-cove
    wl-clipboard
    wl-clip-persist
    swaybg
    brightnessctl
    playerctl
    swaynotificationcenter
  ];

  # Enable GTK primary paste (middle-click paste / selection clipboard in Ghostty and GTK apps)
  dconf.settings."org/gnome/desktop/interface".gtk-enable-primary-paste = true;

  # --- Waybar (styled per cebem1nt dotfiles: floating pill modules, drawers, Tokyo Night) ---
  programs.waybar = {
    enable = true;
    settings = {
      mainBar = {
        layer = "top";
        position = "top";
        height = 28;
        margin-top = 6;
        margin-left = 10;
        margin-right = 10;

        modules-left = [ "group/left-hidden-top" "group/left" ];
        modules-center = [ "clock" ];
        modules-right = [ "group/right" "group/right-hidden-top" ];

        "group/left-hidden-top" = {
          orientation = "horizontal";
          modules = [ "power-profiles-daemon" "group/left-hidden" ];
        };

        "group/left-hidden" = {
          orientation = "horizontal";
          drawer = {
            transition-duration = 500;
            transition-left-to-right = false;
            click-to-reveal = true;
          };
          modules = [ "custom/arrow-right" "battery" "cpu" "load" ];
        };

        "group/left" = {
          orientation = "horizontal";
          modules = [ "niri/workspaces" "mpris" ];
        };

        "clock" = {
          interval = 1;
          format = "{:%H:%M}";
          format-alt = "{:%A, %d %B %Y  %H:%M:%S}";
          tooltip-format = "<tt><small>{calendar}</small></tt>";
          calendar = {
            mode = "year";
            weeks-pos = "right";
            mode-mon-col = 3;
            format = {
              months = "<span color='#acb0d0'><b>{}</b></span>";
              weeks = "<span color='#7aa2f7'><b>W{}</b></span>";
              weekdays = "<span color='#e0af68'><b>{}</b></span>";
              days = "<span color='#acb0d0'><b>{}</b></span>";
              today = "<span color='#41a6b5'><b><u>{}</u></b></span>";
            };
          };
        };

        "group/right" = {
          orientation = "horizontal";
          modules = [
            "bluetooth"
            "group/group-volume"
            "group/group-backlight"
            "network"
            "tray"
          ];
        };

        "group/group-volume" = {
          orientation = "horizontal";
          drawer = {
            transition-duration = 500;
            transition-left-to-right = true;
            click-to-reveal = false;
          };
          modules = [ "pulseaudio" "pulseaudio/slider" ];
        };

        "group/group-backlight" = {
          orientation = "horizontal";
          drawer = {
            transition-duration = 500;
            transition-left-to-right = true;
            click-to-reveal = false;
          };
          modules = [ "backlight" "backlight/slider" ];
        };

        "group/right-hidden-top" = {
          orientation = "horizontal";
          modules = [ "group/right-hidden" "custom/ctlcenter" ];
        };

        "group/right-hidden" = {
          orientation = "horizontal";
          drawer = {
            transition-duration = 500;
            transition-left-to-right = true;
            click-to-reveal = true;
          };
          modules = [ "custom/arrow-left" "memory" "temperature" ];
        };

        "niri/workspaces" = {
          format = "{icon}";
          on-scroll-up = "niri msg action focus-workspace-up";
          on-scroll-down = "niri msg action focus-workspace-down";
          format-icons = {
            active = "󰮯";
            default = "";
            empty = "";
          };
        };

        "mpris" = {
          format = "{artist} - {title}";
          tooltip-format = "{album}";
          format-paused = " {artist} - {title}";
          on-click = "playerctl play-pause";
          on-scroll-up = "playerctl previous";
          on-scroll-down = "playerctl next";
          max-length = 35;
        };

        "cpu" = {
          interval = 5;
          format = " {usage}%";
          states = {
            warning = 70;
            critical = 90;
          };
        };

        "load" = {
          interval = 10;
          format = " {load1}";
        };

        "memory" = {
          interval = 10;
          format = " {used:0.1f}G/{total:0.1f}G";
          states = {
            warning = 75;
            critical = 90;
          };
        };

        "temperature" = {
          interval = 10;
          format = "{icon} {temperatureC}°C";
          critical-threshold = 80;
          format-icons = [ "" "" "" "" "" ];
        };

        "battery" = {
          interval = 20;
          full-at = 90;
          tooltip = true;
          format = "{icon} {capacity}%";
          format-charging = " {capacity}%";
          format-icons = [ "󰁺" "󰁻" "󰁼" "󰁽" "󰁾" "󰁿" "󰂀" "󰂂" "󰁹" ];
          states = {
            warning = 30;
            critical = 15;
          };
        };

        "power-profiles-daemon" = {
          format = "{icon}";
          tooltip-format = "Power profile: {profile}";
          format-icons = {
            performance = "";
            balanced = "";
            power-saver = "";
          };
        };

        "network" = {
          interval = 10;
          format-disabled = "󰌙";
          format-disconnected = "󰌙";
          format-wifi = "";
          format-ethernet = "";
          tooltip-format = "{essid} ({signalStrength}%)";
        };

        "bluetooth" = {
          format = "{icon}";
          format-disabled = "󰂲";
          format-off = "󰂲";
          format-on = "󰂰";
          format-connected = "󰂱 {device_alias}";
          tooltip-format = "{controller_alias}\t{controller_address}";
          tooltip-format-connected = "{controller_alias}\t{controller_address}\n\n{device_enumerate}";
          tooltip-format-enumerate-connected = "{device_alias}\t{device_address}";
        };

        "pulseaudio" = {
          format = "{icon}";
          format-bluetooth = "{icon} 󰂰";
          tooltip-format = "{volume}%";
          format-muted = "";
          scroll-step = 2;
          on-click = "wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle";
          format-icons = {
            headphone = "";
            hands-free = "";
            headset = "";
            phone = "";
            portable = "";
            car = "";
            default = [ "" "" "" ];
          };
        };

        "pulseaudio/slider" = {
          min = 0;
          max = 100;
          orientation = "horizontal";
        };

        "backlight" = {
          scroll-step = 2;
          format = "{icon}";
          tooltip-format = "{percent}%";
          format-icons = [ "󰃞" "󰃝" "󰃟" "󰃠" ];
        };

        "backlight/slider" = {
          min = 5;
          max = 100;
          orientation = "horizontal";
        };

        "tray" = {
          icon-size = 14;
          spacing = 10;
        };

        "custom/arrow-left" = {
          format = "";
          tooltip = false;
        };

        "custom/arrow-right" = {
          format = "";
          tooltip = false;
        };

        "custom/ctlcenter" = {
          tooltip = false;
          format = "";
          on-click = "swaync-client -t -sw";
        };
      };
    };

    style = ''
      /* Tokyo Night Dark Enhanced (cebem1nt style) */
      @define-color module-bg     rgba(8, 8, 11, 0.9);
      @define-color tooltip-bg    rgba(8, 8, 11, 0.95);
      @define-color inactive      #787c99;
      @define-color fg            #acb0d0;
      @define-color workspace-fg  #acb0d0;
      @define-color highlight     #787c99;
      @define-color border        #252525;

      @define-color red           #f7768e;
      @define-color blue          #7aa2f7;
      @define-color yellow        #e0af68;
      @define-color green         #41a6b5;

      * {
        font-family: 'CaskaydiaCove Nerd Font Propo', 'JetBrainsMono Nerd Font', monospace;
        border: none;
        border-radius: 0;
        min-height: 0;
        margin: 0;
        padding: 0;
        text-shadow: none;
      }

      #waybar {
        font-weight: 700;
        background: transparent;
        font-size: 13px;
        color: @fg;
      }

      /* Global module padding */
      #temperature,
      #bluetooth, 
      #battery, 
      #memory,
      #mpris,
      #window,
      #cpu, 
      #load {
        padding: 1px 7px;
      }

      #network, 
      #tray {
        padding: 1px 6px;
      }

      #backlight,
      #pulseaudio {
        padding: 1px 8px;
      }

      #pulseaudio {
        padding-left: 4px;
      }

      #backlight-slider,
      #pulseaudio-slider {
        padding: 0 7px 0 2px;
      }

      #workspaces, 
      #bluetooth, 
      #battery, 
      #memory, 
      #temperature, 
      #cpu,
      #mpris,
      #window,
      #load {
        margin: 0 3px;
      } 

      /* Floating pill-shaped modules */
      #right, 
      #left,
      #right-hidden-top, 
      #left-hidden-top,
      #clock {
        padding: 2px 10px;
        border-radius: 15px;
        background: @module-bg;
        border: 1px solid @border;
      }

      #right-hidden-top,
      #left-hidden-top {
        padding: 0 12px;
      }

      #right, #left {
        margin: 0 8px;
      }

      #clock {
        padding: 2px 18px;
      }

      #custom-ctlcenter {
        margin-left: 7px;
      }

      #power-profiles-daemon {
        margin-right: 7px;
      }

      #cpu.critical,
      #memory.critical, 
      #battery.critical,
      #network.disabled,
      #temperature.critical, 
      #network.disconnected,
      #power-profiles-daemon.performance {
        color: @red;
      }

      #cpu.warning,
      #memory.warning, 
      #battery.warning,
      #temperature.warning {
        color: @yellow;
        background: unset;
      }

      #power-profiles-daemon.power-saver {
        color: @green;
      }

      #custom-ctlcenter {
        color: @blue;
      }

      #workspaces button {
        color: @workspace-fg;
        font-size: 14px;
        border-radius: 100%;
        padding: 0 2px;
        margin: 0 3px;
        min-width: 16px;
      }

      #workspaces button:hover {
        background: transparent;
      }

      #workspaces button.active,
      #workspaces button.focused {
        color: @blue;
      }

      #mpris.paused {
        color: @inactive;
      }

      /* Tooltips */
      tooltip,
      tooltip.background {
        background-image: none;
        border-radius: 15px;
        background: @tooltip-bg;
        box-shadow: none;
      }

      tooltip {
        border: 1px solid @border;
      }

      tooltip label {
        padding: 3px 10px;
        color: @fg;
        font-weight: 700;
      }

      .popup * {
        box-shadow: none;
        outline: none;
        border-radius: 10px;
      }

      menu {
        border-radius: 10px;
        font-weight: 700;
        color: @fg;
        background: @tooltip-bg;
        border: 1px solid @border;
      }

      menu > * {
        padding: 3px 0px;
      }

      menu > *:hover {
        border-radius: 10px;
        background-color: @highlight;
      }

      /* Sliders */
      slider {
        opacity: 0;
        box-shadow: none;
      }

      trough {
        min-width: 50px;
        min-height: 5px;
        border-radius: 8px;
        background: @inactive;
      }

      trough highlight {
        border-radius: 8px;
        background-color: @fg;
        background-image: none;
      }
    '';
  };

  # --- SwayNC Notification Center & Control Center ---
  # Configured via xdg.configFile (rather than services.swaync systemd unit)
  # so it is spawned exclusively inside Niri and does not conflict with GNOME Shell's
  # notification daemon when rebuilding or logging into GNOME.
  xdg.configFile."swaync/config.json".text = builtins.toJSON {
    positionX = "right";
    positionY = "top";
    layer = "overlay";
    control-center-layer = "top";
    control-center-width = 380;
    control-center-height = 600;
    control-center-margin-top = 10;
    control-center-margin-bottom = 10;
    control-center-margin-right = 10;
    control-center-margin-left = 10;
    notification-window-width = 380;
    fit-to-screen = false;
    widgets = [
      "title"
      "dnd"
      "notifications"
      "mpris"
      "volume"
      "backlight"
    ];
    widget-config = {
      title = {
        text = "Notifications";
        clear-all-button = true;
        button-text = "Clear All";
      };
      dnd = {
        text = "Do Not Disturb";
      };
      volume = {
        label = "󰕾";
      };
      backlight = {
        label = "󰃟";
      };
    };
  };

  # --- Hyprlock Screen Locker ---
  programs.hyprlock = {
    enable = true;
    settings = {
      general = {
        disable_loading_bar = true;
        hide_cursor = true;
        grace = 0;
        no_fade_in = false;
      };
      background = [
        {
          path = "screenshot";
          blur_passes = 3;
          blur_size = 8;
          brightness = 0.5;
        }
      ];
      input-field = [
        {
          size = "260, 50";
          outline_thickness = 2;
          dots_size = 0.2;
          dots_spacing = 0.2;
          dots_center = true;
          outer_color = "rgb(122, 162, 247)";
          inner_color = "rgb(26, 27, 38)";
          font_color = "rgb(172, 176, 208)";
          fade_on_empty = false;
          placeholder_text = "<span foreground=\"##787c99\"><i>Password...</i></span>";
          hide_input = false;
          check_color = "rgb(122, 162, 247)";
          fail_color = "rgb(247, 118, 142)";
          fail_text = "<i>$FAIL <b>($ATTEMPTS)</b></i>";
          capslock_color = "rgb(224, 175, 104)";
          position = "0, -20";
          halign = "center";
          valign = "center";
        }
      ];
      label = [
        {
          text = "$TIME";
          color = "rgb(172, 176, 208)";
          font_size = 64;
          font_family = "JetBrainsMono Nerd Font";
          position = "0, 80";
          halign = "center";
          valign = "center";
        }
      ];
    };
  };

  # --- Hypridle Daemon Configuration ---
  # Spawned by Niri at startup (via spawn-at-startup "hypridle")
  xdg.configFile."hypr/hypridle.conf".text = ''
    general {
      lock_cmd = pidof hyprlock || hyprlock
      before_sleep_cmd = loginctl lock-session
      after_sleep_cmd = niri msg action power-on-monitors
    }

    listener {
      timeout = 300
      on-timeout = loginctl lock-session
    }

    listener {
      timeout = 330
      on-timeout = niri msg action power-off-monitors
      on-resume = niri msg action power-on-monitors
    }

    listener {
      timeout = 1800
      on-timeout = systemctl suspend
    }
  '';

  # --- Niri Compositor Configuration ---
  xdg.configFile."niri/config.kdl".text = ''
    // Input Configuration
    input {
      keyboard {
        xkb {
          layout "gb"
        }
      }
      touchpad {
        tap
        natural-scroll
        accel-speed 0.2
      }
    }

    // Framework 13 Display Output (2880x1920 @ 1.5x scale)
    output "eDP-1" {
      scale 1.5
      variable-refresh-rate
    }

    // Appearance & Layout
    prefer-no-csd

    layout {
      gaps 8
      center-focused-column "never"

      default-column-width { proportion 0.5; }

      preset-column-widths {
        proportion 0.33333
        proportion 0.5
        proportion 0.66667
        proportion 1.0
      }

      focus-ring {
        width 2
        active-color "#7aa2f7"
        inactive-color "#252525"
      }

      border {
        off
      }
    }

    // Screenshot destination
    screenshot-path "~/Pictures/Screenshots/Screenshot from %Y-%m-%d %H-%M-%S.png"

    // Autostart services
    spawn-at-startup "${polkitAgent}"
    spawn-at-startup "swaybg" "-i" "/home/chris/Pictures/DSC00478.jpg" "-m" "fill"
    spawn-at-startup "wl-clip-persist" "--clipboard" "both"
    spawn-at-startup "swaync"
    spawn-at-startup "elephant"
    spawn-at-startup "walker" "--gapplication-service"
    spawn-at-startup "waybar"
    spawn-at-startup "hypridle"

    // Keybindings (Mod = Super)
    binds {
      Mod+Shift+Slash { show-hotkey-overlay; }

      // Applications & Launchers
      Mod+Return { spawn "ghostty"; }
      Mod+T { spawn "ghostty"; }
      Mod+D { spawn "walker"; }
      Mod+Space { spawn "walker"; }
      Mod+Shift+D { spawn "fuzzel"; }

      // Notifications & Lock
      Mod+N { spawn "swaync-client" "-t" "-sw"; }
      Super+Alt+L { spawn "hyprlock"; }
      Mod+Escape { spawn "hyprlock"; }

      // Window Management
      Mod+Q { close-window; }
      Mod+Shift+E { quit skip-confirmation=true; }

      // Column Focus (Vim keys & Arrows)
      Mod+H { focus-column-left; }
      Mod+L { focus-column-right; }
      Mod+J { focus-window-down; }
      Mod+K { focus-window-up; }
      Mod+Left { focus-column-left; }
      Mod+Right { focus-column-right; }
      Mod+Down { focus-window-down; }
      Mod+Up { focus-window-up; }

      // Column Movement
      Mod+Shift+H { move-column-left; }
      Mod+Shift+L { move-column-right; }
      Mod+Shift+J { move-window-down; }
      Mod+Shift+K { move-window-up; }
      Mod+Shift+Left { move-column-left; }
      Mod+Shift+Right { move-column-right; }
      Mod+Shift+Down { move-window-down; }
      Mod+Shift+Up { move-window-up; }

      // Workspaces
      Mod+1 { focus-workspace 1; }
      Mod+2 { focus-workspace 2; }
      Mod+3 { focus-workspace 3; }
      Mod+4 { focus-workspace 4; }
      Mod+5 { focus-workspace 5; }
      Mod+6 { focus-workspace 6; }
      Mod+7 { focus-workspace 7; }
      Mod+8 { focus-workspace 8; }
      Mod+9 { focus-workspace 9; }

      Mod+Shift+1 { move-column-to-workspace 1; }
      Mod+Shift+2 { move-column-to-workspace 2; }
      Mod+Shift+3 { move-column-to-workspace 3; }
      Mod+Shift+4 { move-column-to-workspace 4; }
      Mod+Shift+5 { move-column-to-workspace 5; }
      Mod+Shift+6 { move-column-to-workspace 6; }
      Mod+Shift+7 { move-column-to-workspace 7; }
      Mod+Shift+8 { move-column-to-workspace 8; }
      Mod+Shift+9 { move-column-to-workspace 9; }

      // Mouse wheel workspace scrolling
      Mod+WheelScrollDown cooldown-ms=150 { focus-workspace-down; }
      Mod+WheelScrollUp   cooldown-ms=150 { focus-workspace-up; }

      // Layout & Sizing
      Mod+R { switch-preset-column-width; }
      Mod+Shift+R { switch-preset-column-width-back; }
      Mod+F { maximize-column; }
      Mod+Shift+F { fullscreen-window; }
      Mod+C { center-column; }
      Mod+Minus { set-column-width "-10%"; }
      Mod+Equal { set-column-width "+10%"; }
      Mod+V { toggle-window-floating; }
      Mod+Shift+V { switch-focus-between-floating-and-tiling; }

      // Audio (PipeWire / WirePlumber)
      XF86AudioRaiseVolume allow-when-locked=true { spawn "wpctl" "set-volume" "-l" "1.0" "@DEFAULT_AUDIO_SINK@" "5%+"; }
      XF86AudioLowerVolume allow-when-locked=true { spawn "wpctl" "set-volume" "@DEFAULT_AUDIO_SINK@" "5%-"; }
      XF86AudioMute        allow-when-locked=true { spawn "wpctl" "set-mute" "@DEFAULT_AUDIO_SINK@" "toggle"; }
      XF86AudioMicMute     allow-when-locked=true { spawn "wpctl" "set-mute" "@DEFAULT_AUDIO_SOURCE@" "toggle"; }

      // Media controls
      XF86AudioPlay allow-when-locked=true { spawn "playerctl" "play-pause"; }
      XF86AudioPrev allow-when-locked=true { spawn "playerctl" "previous"; }
      XF86AudioNext allow-when-locked=true { spawn "playerctl" "next"; }

      // Brightness (brightnessctl)
      XF86MonBrightnessUp   allow-when-locked=true { spawn "brightnessctl" "--class=backlight" "set" "+5%"; }
      XF86MonBrightnessDown allow-when-locked=true { spawn "brightnessctl" "--class=backlight" "set" "5%-"; }

      // Screenshots
      Print { screenshot; }
      Mod+Print { screenshot-window; }
      Mod+Shift+Print { screenshot-screen; }
    }
  '';
}
