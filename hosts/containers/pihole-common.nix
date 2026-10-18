{ config, pkgs, lib, ... }:

let
  cliPw = "${config.services.pihole-ftl.configDirectory}/cli_pw";
  textfileDir = "/var/lib/node-exporter-textfile";
in
{
  imports = [
    ../../modules/file-logs.nix
  ];

  # Open firewall ports and set custom DNS to avoid loops
  networking = {
    firewall = {
      allowedTCPPorts = [ 22 53 80 443];
      allowedUDPPorts = [ 53 ];
    };
  };


  services.pihole-ftl = {
    enable = true;
    openFirewallDHCP = true;

    queryLogDeleter.enable = true;
    # NO `lists` here — it is what creates pihole-ftl-setup.service, which
    # fails on every boot. The adlists live in gravity.db (state, not config)
    # and pihole-gravity-update below rebuilds from them.
    # why: docs/notes.md#container-one-offs
    settings = {
      dns = {
        domainNeeded = true;
        expandHosts = true;
        interface = "eth0";
        listeningMode = "BIND";
        upstreams = [
            "1.1.1.1#53"
            "1.0.0.1#53"
            "2606:4700:4700::1111#53"
            "2606:4700:4700::1001#53"
        ];
        # Default is 1000 queries/60s per client; bumped 10x for busy clients.
        # Set count = 0 to disable rate limiting entirely.
        rateLimit = {
          count = 10000;
          interval = 60;
        };
      };
      dhcp = {
        active = false;

      };
      webserver.api = {
        pwhash = "$BALLOON-SHA256$v=1$s=1024,t=32$0ryHODlDWJn1L0uBamA2Zg==$zq/YS/1/qOqhbXbcoKGf7hdWWVv3Tqd0Dn7iVwYKAf4=";
      };
    };
  };


    services.pihole-web = {
        enable = true;
        ports = [ 80 ];
    };

  # Update gravity database on boot and daily
  systemd.services.pihole-gravity-update = {
    description = "Update Pi-hole gravity database";
    after = [ "pihole-ftl.service" "network-online.target" ];
    wants = [ "network-online.target" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.bash}/bin/bash -c '/run/current-system/sw/bin/pihole -g'";
    };
  };

  systemd.timers.pihole-gravity-update = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "10min";
      OnUnitActiveSec = "24h";
    };
  };

  # FTL's own log and the webserver log. pihole.log is the per-query log (every
  # lookup), so it stays out of the journal; the web UI already has it.
  services.fileLogs = {
    pihole-ftl = "${config.services.pihole-ftl.logDirectory}/FTL.log";
    pihole-webserver = "${config.services.pihole-ftl.logDirectory}/webserver.log";
  };

  # Stats for Prometheus, written as a textfile for node_exporter. The packaged
  # exporter (eko/pihole-exporter 1.2.0) logs in on every request (1.5-4s of FTL
  # CPU each) and wedges after a timeout on v6 (upstream #332), so this reads the
  # summary every 5 minutes instead. cli_pw is regenerated on each FTL restart,
  # so it is read fresh each run. why: docs/notes.md#prometheus-and-journal-remote
  services.prometheus.exporters.node = {
    enabledCollectors = [ "textfile" ];
    extraFlags = [ "--collector.textfile.directory=${textfileDir}" ];
  };
  systemd.tmpfiles.rules = [ "d ${textfileDir} 0755 root root -" ];

  systemd.services.pihole-metrics = {
    description = "Write Pi-hole stats as Prometheus textfile metrics";
    after = [ "pihole-ftl.service" ];
    path = [ pkgs.coreutils pkgs.curl pkgs.jq ];
    serviceConfig.Type = "oneshot";
    script = ''
      set -eu -o pipefail
      dir=${textfileDir}
      api=http://127.0.0.1/api
      tmp=$(mktemp "$dir/.pihole.XXXXXX")
      trap 'rm -f "$tmp"' EXIT

      sid=$(jq -cn --rawfile pw ${cliPw} '{password: ($pw | rtrimstr("\n"))}' \
        | curl -sf --max-time 20 -X POST "$api/auth" --data @- \
        | jq -r '.session.sid // empty') || sid=

      if [ -n "$sid" ] && stats=$(curl -sf --max-time 20 -H "X-FTL-SID: $sid" "$api/stats/summary"); then
        curl -s --max-time 5 -X DELETE -H "X-FTL-SID: $sid" "$api/auth" >/dev/null || true
        jq -r '
          "pihole_up 1",
          "pihole_queries \(.queries.total // 0)",
          "pihole_queries_blocked \(.queries.blocked // 0)",
          "pihole_queries_blocked_percent \(.queries.percent_blocked // 0)",
          "pihole_queries_forwarded \(.queries.forwarded // 0)",
          "pihole_queries_cached \(.queries.cached // 0)",
          "pihole_unique_domains \(.queries.unique_domains // 0)",
          "pihole_clients_active \(.clients.active // 0)",
          "pihole_domains_being_blocked \(.gravity.domains_being_blocked // 0)",
          "pihole_gravity_last_update_timestamp_seconds \(.gravity.last_update // 0)"
        ' <<<"$stats" > "$tmp"
      else
        echo 'pihole_up 0' > "$tmp"
      fi
      chmod 0644 "$tmp"
      mv "$tmp" "$dir/pihole.prom"
    '';
  };

  systemd.timers.pihole-metrics = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "2min";
      OnUnitActiveSec = "5min";
    };
  };




  ### Packages
  environment.systemPackages = with pkgs; [
    dig
  ];

  # ── Disable systemd-resolved (conflicts on port 53) ─────────────────────────
  services.resolved.enable = false;

  # NOT 127.0.0.1 — that deadlocks the boot. why: docs/notes.md#container-one-offs
  networking.nameservers = lib.mkForce [
    "1.1.1.1"
    "1.0.0.1"
    "2606:4700:4700::1111"
    "2606:4700:4700::1001"
  ];



}
