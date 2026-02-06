{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.keyboard-backlight-timeout;
in
{
  options.services.keyboard-backlight-timeout = {
    enable = mkEnableOption "automatic keyboard backlight timeout on idle";

    timeout = mkOption {
      type = types.int;
      default = 30;
      description = "Number of seconds of inactivity before turning off the keyboard backlight";
    };

    brightnessMax = mkOption {
      type = types.int;
      default = 100;
      description = "Maximum brightness level when active";
    };
  };

  config = mkIf cfg.enable {
    # Make keyboard backlight writable by video group
    services.udev.extraRules = ''
      ACTION=="add", SUBSYSTEM=="leds", KERNEL=="*kbd_backlight", RUN+="${pkgs.coreutils}/bin/chmod g+w /sys/class/leds/%k/brightness", GROUP="video"
    '';

    # Add root to video group for backlight control
    users.users.root.extraGroups = [ "video" ];

    # Keyboard backlight auto-timeout service
    systemd.services.keyboard-backlight-timeout = {
      description = "Auto-dim keyboard backlight after inactivity";
      wantedBy = [ "multi-user.target" ];
      after = [ "multi-user.target" "systemd-udev-settle.service" ];
      serviceConfig = {
        Type = "simple";
        SupplementaryGroups = "video input";
        ExecStart = "${pkgs.python3.withPackages (ps: [ ps.evdev ])}/bin/python3 ${pkgs.writeText "kbd-backlight-timeout.py" ''
          #!/usr/bin/env python3
          import glob
          import time
          import select
          from evdev import InputDevice

          TIMEOUT = ${toString cfg.timeout}
          BRIGHTNESS_MAX = ${toString cfg.brightnessMax}
          BRIGHTNESS_OFF = 0

          # Find keyboard backlight device
          kbd_backlight_paths = glob.glob('/sys/class/leds/*kbd*backlight*/brightness') + \
                                glob.glob('/sys/class/leds/*keyboard*/brightness')

          if not kbd_backlight_paths:
              print("ERROR: Keyboard backlight device not found")
              exit(1)

          kbd_backlight = kbd_backlight_paths[0]
          print(f"Using keyboard backlight: {kbd_backlight}")

          # Open all input devices
          devices = []
          for path in glob.glob('/dev/input/event*'):
              try:
                  dev = InputDevice(path)
                  devices.append(dev)
                  print(f"Monitoring: {dev.name} ({path})")
              except Exception as e:
                  print(f"Cannot open {path}: {e}")

          if not devices:
              print("ERROR: No input devices found")
              exit(1)

          def set_brightness(value):
              try:
                  with open(kbd_backlight, 'w') as f:
                      f.write(str(value))
                  return True
              except Exception as e:
                  print(f"ERROR: Cannot set brightness: {e}")
                  return False

          # Turn on backlight initially
          if not set_brightness(BRIGHTNESS_MAX):
              exit(1)

          last_activity = time.time()
          backlight_on = True

          print("Monitoring for input activity...")

          while True:
              # Use select to wait for input with 1 second timeout
              r, w, x = select.select(devices, [], [], 1.0)

              current_time = time.time()

              if r:  # Input activity detected
                  # Clear the events
                  for dev in r:
                      try:
                          for event in dev.read():
                              pass
                      except:
                          pass

                  last_activity = current_time

                  if not backlight_on:
                      if set_brightness(BRIGHTNESS_MAX):
                          backlight_on = True
                          print("Backlight ON (activity detected)")

              # Check timeout
              idle_time = current_time - last_activity

              if idle_time >= TIMEOUT and backlight_on:
                  if set_brightness(BRIGHTNESS_OFF):
                      backlight_on = False
                      print(f"Backlight OFF ({TIMEOUT} s timeout)")
        ''}";
        Restart = "always";
        RestartSec = "5s";
      };
    };
  };
}
