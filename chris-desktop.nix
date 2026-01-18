# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).

{ config, pkgs, ... }:

{
  imports =
    [ # Include the results of the hardware scan.
      ./hardware-configuration-desktop.nix
    ];

  # Bootloader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  # Use latest kernel.
  boot.kernelPackages = pkgs.linuxPackages_latest;
  
powerManagement.enable = true;

nix.gc = {
  automatic = true;
  dates = "weekly";
  options = "--delete-older-than 14d";
};

boot.kernelModules = [ "sg" ];
  # Enable plymouth
  boot.plymouth.enable = true;

  networking.hostName = "chris-desktop"; # Define your hostname.
  # networking.wireless.enable = true;  # Enables wireless support via wpa_supplicant.

  # Enable networking
  networking.networkmanager.enable = true;

  # Set your time zone.
  time.timeZone = "Europe/London";

  # Select internationalisation properties.
  i18n.defaultLocale = "en_GB.UTF-8";

  i18n.extraLocaleSettings = {
    LC_ADDRESS = "en_GB.UTF-8";
    LC_IDENTIFICATION = "en_GB.UTF-8";
    LC_MEASUREMENT = "en_GB.UTF-8";
    LC_MONETARY = "en_GB.UTF-8";
    LC_NAME = "en_GB.UTF-8";
    LC_NUMERIC = "en_GB.UTF-8";
    LC_PAPER = "en_GB.UTF-8";
    LC_TELEPHONE = "en_GB.UTF-8";
    LC_TIME = "en_GB.UTF-8";
  };

  # Enable the X11 windowing system.
  services.xserver.enable = true;

  # Enable the GNOME Desktop Environment.
  services.xserver.displayManager.gdm.enable = true;
  services.xserver.desktopManager.gnome.enable = true;
  services.xserver.desktopManager.gnome.extraGSettingsOverridePackages = [ pkgs.mutter ];
  services.xserver.desktopManager.gnome.extraGSettingsOverrides = ''
  [org.gnome.mutter]
  experimental-features=['scale-monitor-framebuffer','xwayland-native-scaling','variable-refresh-rate']
'';

  # Configure keymap in X11
  services.xserver.xkb = {
    layout = "gb";
    variant = "";
  };

  # Configure console keymap
  console.keyMap = "uk";

  # Enable CUPS to print documents.
  services.printing.enable = true;

## adding lilnas

fileSystems."/home/chris/Media" = {
  device = "//lilnas.mcneill.fyi/Media";
  fsType = "cifs";
  options = let
    # x-systemd.automount is the secret sauce here
    automount_opts = "x-systemd.automount,noauto,x-systemd.idle-timeout=60,x-systemd.device-timeout=5s,mount-timeout=5s";
  in ["${automount_opts},username=chris,uid=1000,gid=100,vers=3.0"];
};
  # Enable sound with pipewire.
  services.pulseaudio.enable = false;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    wireplumber.enable = true;    
    # If you want to use JACK applications, uncomment this
    #jack.enable = true;

    # use the example session manager (no others are packaged yet so this is enabled by default,
    # no need to redefine it in your config for now)
    #media-session.enable = true;
  };

  # Enable touchpad support (enabled default in most desktopManager).
  # services.xserver.libinput.enable = true;

  # Define a user account. Don't forget to set a password with ‘passwd’.
  users.users.chris = {
    isNormalUser = true;
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIK1z+ixouoLpNHXciINsW1Jlvcmnr9E2ekFXCvvjBxfh"  # Same key as before
    ];
    description = "Chris";
    extraGroups = [ "networkmanager" "wheel" "docker" "libvirtd" "cdrom" "arm"];
    packages = with pkgs; [
    beeper
    qgis
    git
    vscode
    spotify
    conda
    fastfetch
    powertop
    dig
	  fprintd
	  teams-for-linux
    google-fonts
    nixos-generators
    drawio
    wget
    gnome-boxes
    google-chrome
    gamescope
    vulkan-tools
    lsscsi
    docker-compose
    makemkv
    sysstat
    handbrake
    filebot
    btop
    darktable
    ];
  };

  programs.gamescope = {
    enable = true;
    capSysNice = true;
  };


hardware.graphics = {
  enable = true;
  enable32Bit = true;
};
 
hardware.amdgpu = {
  initrd.enable = true;
  opencl.enable = true;
};
environment.systemPackages = with pkgs; [
  ffmpeg-full
];




  programs.steam.gamescopeSession.enable = true; # Integrates with programs.steam





  services.fprintd.enable = true;
  services.flatpak.enable = true;

  virtualisation.libvirtd.enable = true;
  programs.virt-manager.enable = true;
  users.groups = {
    libvirtd.members = [ "chris" ];
    kvm.members = [ "chris" ];
  };



  hardware.bluetooth = {
    enable = true;
    powerOnBoot = true;
    settings = {
      General = {
        # Shows battery charge of connected devices on supported
        # Bluetooth adapters. Defaults to 'false'.
        Experimental = true;
        # When enabled other devices can connect faster to us, however
        # the tradeoff is increased power consumption. Defaults to
        # 'false'.
        FastConnectable = true;
      };
      Policy = {
        # Enable all controllers when they are found. This includes
        # adapters present on start as well as adapters that are plugged
        # in later on. Defaults to 'true'.
        AutoEnable = true;
      };
    };
  };

  # Install firefox.
  programs.firefox.enable = true;
  #enable powertop for power tuning
  #powerManagement.powertop.enable = true;
  # install steam
  programs.steam = {
    enable = true;
    remotePlay.openFirewall = true; # Open ports in the firewall for Steam Remote Play
    dedicatedServer.openFirewall = true; # Open ports in the firewall for Source Dedicated Server
};

  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;


  programs._1password.enable = true;
  programs._1password-gui = {
    enable = true;
    # Certain features, including CLI integration and system authentication support,
    # require enabling PolKit integration on some desktop environments (e.g. Plasma).
    polkitPolicyOwners = [ "chris" ];
  };

  # Enable SSH server
  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "no";
      PasswordAuthentication = false;
    };
  };

  services.sunshine = {
    enable = true;
    autoStart = true;
    capSysAdmin = true;
    openFirewall = true;
    
  };


  ###
  # Disable problematic wake sources
  systemd.services.disable-wake-sources = {
    description = "Disable USB wake sources";
    wantedBy = [ "multi-user.target" ];
    after = [ "multi-user.target" ];
    script = ''
      echo GPP0 > /proc/acpi/wakeup
      echo GPP8 > /proc/acpi/wakeup
      # Add XHC0/XHC1 if USB controllers are the issue
      # echo XHC0 > /proc/acpi/wakeup
    '';
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
  };

  virtualisation.docker.enable = true;


  fileSystems."/mnt/Media" = {
    device = "192.168.1.12:/mnt/Hutch/Media";
    fsType = "nfs";
    options = [ "x-systemd.automount" "noauto" "x-systemd.idle-timeout=600"];
  };
  
  # optional, but ensures rpc-statsd is running for on demand mounting
  boot.supportedFilesystems = [ "nfs" ];
  services.rpcbind.enable = true; # needed for NFS

   systemd.automounts = [{
    wantedBy = [ "multi-user.target" ];
    automountConfig = {
      TimeoutIdleSec = "600";
    };
    where = "/mnt/Media";
  }];

  # Open firewall for SSH
  networking.firewall.allowedTCPPorts = [ 22 ];

  # Some programs need SUID wrappers, can be configured further or are
  # started in user sessions.
  # programs.mtr.enable = true;
  # programs.gnupg.agent = {
  #   enable = true;
  #   enableSSHSupport = true;
  # };

  # List services that you want to enable:

  # Enable the OpenSSH daemon.
  # services.openssh.enable = true;

  # Open ports in the firewall.
  # networking.firewall.allowedTCPPorts = [ ... ];
  # networking.firewall.allowedUDPPorts = [ ... ];
  # Or disable the firewall altogether.
  # networking.firewall.enable = false;

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It‘s perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "25.11"; # Did you read the comment?


}

