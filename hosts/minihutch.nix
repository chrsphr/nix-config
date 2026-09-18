{ config, pkgs, pkgs-unstable, sops-nix, gb-grid, gb-grid-pkg, lib, ... }:

# minihutch (192.168.1.3): the second baremetal container host — compute
# only, no ZFS/NFS/backup. Runs beeper, caddy, pihole-2, tailscale, uptime.
# why: docs/notes.md#minihutch

let
  keys = import ../modules/keys.nix;
  hostsLib = import ../lib/network.nix { inherit lib; };
in
{
  imports = [
    ../modules/locale.nix
    # Newest ZFS-compatible kernel, shared with hutch — the fleet runs one
    # kernel even though only hutch has ZFS.
    ../modules/kernel-pin.nix
    # LAN bond/bridge + every container with `parent = "minihutch"`.
    ../modules/container-host.nix
  ];

  # ── TV tuner server ──────────────────────────────────────────────────────
  # The Xbox tuner is plugged in here, so TVHeadend reads it directly off the
  # local DVB stack (no USB/IP). Antennas re-exposes TVHeadend as an
  # HDHomeRun, which is the only tuner type Plex's DVR understands.
  # why: docs/notes.md#tvheadend-on-minihutch
  virtualisation.oci-containers = {
    backend = "podman";
    containers = {
      tvheadend = {
        image = "ghcr.io/tvheadend/tvheadend:latest";
        # Root so it can open the root:video DVB nodes regardless of the
        # image's group IDs.
        user = "root:root";
        devices = [ "/dev/dvb" ];
        volumes = [ "/var/lib/tvheadend:/var/lib/tvheadend:rw" ];
        environment.TZ = "Europe/London";
        # --firstrun creates a no-username/no-password account when none
        # exists so the web UI can be reached for first-time setup; it is a
        # no-op once a real user exists (remove it after setup if you like).
        cmd = [ "--firstrun" "--config" "/var/lib/tvheadend" "--nosatip" ];
        # Host networking: simplest for discovery/streaming, and means the
        # NixOS firewall governs the ports below.
        extraOptions = [ "--network=host" ];
        pull = "newer";
      };
      antennas = {
        image = "thejf/antennas:latest";
        dependsOn = [ "tvheadend" ];
        environment = {
          # LAN address, not localhost: Antennas bakes this into the stream
          # URLs in lineup.json, and Plex (on hutch) must be able to reach them.
          TVHEADEND_URL = "http://${hostsLib.getIP "minihutch"}:9981";
          # Address Plex uses to reach the emulated HDHomeRun.
          ANTENNAS_URL = "http://${hostsLib.getIP "minihutch"}:5004";
          TUNER_COUNT = "1";
        };
        extraOptions = [ "--network=host" ];
        pull = "newer";
      };
    };
  };

  # TVHeadend config + recordings live on local disk; Plex does the recording,
  # TVHeadend only serves the live TS.
  systemd.tmpfiles.rules = [ "d /var/lib/tvheadend 0755 root root -" ];

  # 9981 = TVHeadend web UI/HTSP, 5004 = Antennas (HDHomeRun to Plex).
  networking.firewall.allowedTCPPorts = [ 9981 5004 ];

  # The container can't start before the DVB frontend node exists.
  systemd.services."podman-tvheadend" = {
    after = [ "dev-dvb-adapter0-frontend0.device" ];
    wants = [ "dev-dvb-adapter0-frontend0.device" ];
  };

  networking.hostName = "minihutch";

  containerHost = {
    enable = true;

    # Onboard 1GbE MAC — fixed LAN identity for .3. WiFi is never enslaved
    # (bond matches Type=ether only). why: docs/notes.md#minihutch
    macAddress = "10:02:b5:86:02:0a";

    # Age keys placed by hand — docs/minihutch-install.md step 7.
    withSecrets = [ "caddy" "uptime" ];

    perContainer = {
      # /dev/net/tun + CAP_NET_ADMIN for tailscaled.
      tailscale.enableTun = true;
    };
  };

  # Boot loader
  boot.loader = {
    systemd-boot.enable = true;
    # Cap boot entries: the 512M ESP holds ~9 kernel+initrd pairs, and no
    # nix.gc runs here, so generations would otherwise fill /boot and every
    # deploy would die copying the new kernel before the builder prunes.
    systemd-boot.configurationLimit = 5;
    efi.canTouchEfiVariables = true;
  };

  # SSH + deploy user for deploy-rs. Keys only — both options stated on
  # purpose. why: docs/notes.md#hutch
  services.openssh = {
    enable = true;
    openFirewall = true;
    settings = {
      PermitRootLogin = "no";
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
    };
  };
  users.users.deploy = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    openssh.authorizedKeys.keys = [ keys.chris ];
  };
  # chris: interactive login. Same uid as on hutch; password set imperatively
  # on the box on purpose. why: docs/notes.md#hutch
  users.users.chris = {
    isNormalUser = true;
    uid = 1001;
    extraGroups = [ "wheel" ];
    openssh.authorizedKeys.keys = [ keys.chris ];
  };
  users.users.root.openssh.authorizedKeys.keys = [ keys.chris ];
  security.sudo.wheelNeedsPassword = false;

  # Glances system telemetry web API (consumed by Homepage dashboard)
  services.glances = {
    enable = true;
    openFirewall = true;
  };

  # Nix settings
  nix.settings = {
    experimental-features = [ "nix-command" "flakes" ];
    sandbox = false;
    require-sigs = false;
  };

  environment.systemPackages = with pkgs; [
    vim
    htop
    git
  ];

  nixpkgs.config.allowUnfree = true;
  system.stateVersion = "26.05";
}
