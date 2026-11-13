{ network, ... }:

# minihutch (192.168.1.3): the second baremetal container host — compute
# only, no ZFS/NFS/backup. Runs beeper, caddy, pihole-2, tailscale, uptime.
# why: docs/notes.md#minihutch

let
  ip = network.getIP "minihutch";
in
{
  imports = [
    ../modules/server-base.nix
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
          TVHEADEND_URL = "http://${ip}:9981";
          # Address Plex uses to reach the emulated HDHomeRun.
          ANTENNAS_URL = "http://${ip}:5004";
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
    withSecrets = [ "caddy" "uptime" "prometheus" ];

    perContainer = {
      # /dev/net/tun + CAP_NET_ADMIN for tailscaled.
      tailscale.enableTun = true;
    };
  };

  system.stateVersion = "26.05";
}
