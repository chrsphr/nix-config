{ config, pkgs, sops-nix, lib, ... }:

# Prometheus metrics + systemd-journal-remote log sink as a NixOS container on
# minihutch. Targets are derived from lib/network.nix; every host and container
# uploads its journal here over HTTP (:19532). Alertmanager runs alongside
# Prometheus and emails alerts over the Fastmail SMTP relay.
# why: docs/notes.md#prometheus-and-journal-remote

let
  hostsLib = import ../../lib/network.nix { inherit lib; };

  baremetalHosts = [ "hutch" "minihutch" ];
  containerHosts = lib.filterAttrs (_: cfg: cfg ? parent) hostsLib.hosts;

  # Replace the IP:port instance label with the readable hostname from
  # lib/network.nix while preserving the scrape address.
  hostRelabel = [
    {
      source_labels = [ "host" ];
      target_label = "instance";
    }
  ];

  # Helper wrapper so `fleet-logs -p err` or `fleet-logs _HOSTNAME=immich -f`
  # queries the centralized remote journal directory directly.
  fleetLogs = pkgs.writeShellScriptBin "fleet-logs" ''
    exec ${pkgs.systemd}/bin/journalctl -D /var/log/journal/remote "$@"
  '';
in
{
  imports = [
    ./common.nix
    sops-nix.nixosModules.sops
  ];

  networking = {
    hostName = "prometheus";
    # 9090: Prometheus web UI / API. 19532: systemd-journal-remote HTTP sink.
    # Alertmanager stays on loopback: only Prometheus talks to it.
    firewall.allowedTCPPorts = [ 9090 19532 ];
  };

  sops = {
    defaultSopsFile = ../../secrets/prometheus.yaml;
    # A copy of the laptop master key — accepted tradeoff.
    # why: docs/notes.md#secrets-under-var
    age.keyFile = "/var/secrets/keys.txt";
    secrets.smtp_password = {
      # Alertmanager reads this through a systemd credential, so the file
      # itself stays root-only. Rotating it restarts the service.
      path = "/var/lib/sops/smtp_password";
      restartUnits = [ "alertmanager.service" ];
    };
  };

  services.prometheus = {
    enable = true;
    port = 9090;
    retentionTime = "90d";
    webExternalUrl = "https://prometheus.${hostsLib.domain}";

    globalConfig = {
      scrape_interval = "30s";
      evaluation_interval = "30s";
    };

    # Alertmanager shares the container; loopback keeps it off the LAN.
    alertmanagers = [
      {
        static_configs = [
          {
            targets = [ "127.0.0.1:9093" ];
          }
        ];
      }
    ];

    scrapeConfigs = [
      {
        job_name = "prometheus";
        static_configs = [
          {
            targets = [ "127.0.0.1:9090" ];
            labels.host = "prometheus";
          }
        ];
        relabel_configs = hostRelabel;
      }
      {
        job_name = "hosts";
        static_configs = map (name: {
          targets = [ "${hostsLib.getIP name}:9100" ];
          labels.host = name;
        }) baremetalHosts;
        relabel_configs = hostRelabel;
      }
      {
        job_name = "smartctl";
        scrape_interval = "60s";
        static_configs = map (name: {
          targets = [ "${hostsLib.getIP name}:9633" ];
          labels.host = name;
        }) baremetalHosts;
        relabel_configs = hostRelabel;
      }
      {
        job_name = "containers";
        static_configs = lib.mapAttrsToList (name: cfg: {
          targets = [ "${cfg.ip}:9100" ];
          labels = {
            host = name;
            parent = cfg.parent;
          };
        }) containerHosts;
        relabel_configs = hostRelabel;
      }
      {
        job_name = "gatus";
        static_configs = [
          {
            targets = [ "${hostsLib.getIP "uptime"}:3001" ];
            labels.host = "uptime";
          }
        ];
        relabel_configs = hostRelabel;
      }
      {
        job_name = "caddy";
        static_configs = [
          {
            targets = [ "${hostsLib.getIP "caddy"}:9180" ];
            labels.host = "caddy";
          }
        ];
        relabel_configs = hostRelabel;
      }
      {
        job_name = "postgres";
        static_configs = [
          {
            targets = [ "${hostsLib.getIP "gb-grid"}:9187" ];
            labels.host = "gb-grid";
          }
        ];
        relabel_configs = hostRelabel;
      }
    ];

    rules = [
      (builtins.toJSON {
        groups = [
          {
            name = "fleet";
            rules = [
              {
                alert = "TargetDown";
                expr = "up == 0";
                for = "2m";
                labels.severity = "warning";
                annotations.summary = "{{ $labels.job }} target {{ $labels.instance }} is unreachable";
              }
              {
                alert = "SystemdUnitFailed";
                # oneshots are left out: a failed oneshot stays failed until its next run.
                expr = ''node_systemd_unit_state{state="failed",type!="oneshot"} == 1'';
                for = "2m";
                labels.severity = "warning";
                annotations.summary = "systemd unit {{ $labels.name }} failed on {{ $labels.instance }}";
              }
              {
                # Bridges should stay active once bbctl has logged in. bbctl
                # exits 0 on startup DNS failures, so state="failed" misses them.
                alert = "BeeperBridgeDown";
                expr = ''node_systemd_unit_state{host="beeper",name=~"mautrix-.+[.]service",state="active"} == 0'';
                for = "10m";
                labels.severity = "warning";
                annotations.summary = "Beeper bridge {{ $labels.name }} is not active";
              }
              {
                alert = "FilesystemSpaceLow";
                expr = ''(node_filesystem_avail_bytes{fstype!~"tmpfs|ramfs"} / node_filesystem_size_bytes) < 0.10'';
                for = "10m";
                labels.severity = "warning";
                annotations.summary = "Filesystem {{ $labels.mountpoint }} on {{ $labels.instance }} has <10% free";
              }
              {
                alert = "ZfsPoolUnhealthy";
                expr = ''node_zfs_zpool_state{state!="online"} > 0'';
                for = "1m";
                labels.severity = "critical";
                annotations.summary = "ZFS pool {{ $labels.zpool }} on {{ $labels.instance }} is {{ $labels.state }}";
              }
              {
                alert = "SmartDiskUnhealthy";
                expr = "smartctl_device_smart_status != 1";
                for = "5m";
                labels.severity = "critical";
                annotations.summary = "SMART health check failed for {{ $labels.device }} on {{ $labels.instance }}";
              }
              {
                # why: docs/notes.md#disk-apm ("A few hundred per day means back it out")
                alert = "DiskLoadCycleRunaway";
                expr = ''increase(smartctl_device_attribute{attribute_name="Load_Cycle_Count",attribute_value_type="raw"}[1d]) > 300'';
                for = "15m";
                labels.severity = "warning";
                annotations.summary = "High Load_Cycle_Count growth on {{ $labels.device }} ({{ $labels.instance }})";
              }
              {
                # Textfile written by pihole-metrics (hosts/containers/pihole-common.nix).
                alert = "PiholeStatsDown";
                expr = ''pihole_up == 0 or time() - node_textfile_mtime_seconds{file="pihole.prom"} > 900'';
                for = "10m";
                labels.severity = "warning";
                annotations.summary = "Pi-hole stats missing or stale on {{ $labels.instance }}";
              }
            ];
          }
          {
            name = "capacity";
            rules = [
              {
                alert = "HostCpuBusy";
                expr = ''1 - avg by (instance) (rate(node_cpu_seconds_total{mode="idle"}[10m])) > 0.9'';
                for = "30m";
                labels.severity = "warning";
                annotations.summary = "CPU on {{ $labels.instance }} has been over 90% busy for 30m";
              }
              {
                # MemAvailable leaves out ZFS ARC, which is reclaimable, so hutch's
                # cache would read as pressure. Add ARC back where it exists.
                # why: docs/notes.md#prometheus-and-journal-remote
                alert = "HostMemoryLow";
                expr = ''
                  (node_memory_MemAvailable_bytes + node_zfs_arc_size) / node_memory_MemTotal_bytes < 0.10
                  or
                  (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes < 0.10 unless on(instance) node_zfs_arc_size)
                '';
                for = "15m";
                labels.severity = "warning";
                annotations.summary = "Under 10% memory available on {{ $labels.instance }} (ZFS ARC counted as available)";
              }
              {
                alert = "HostSwapHeavy";
                expr = ''1 - node_memory_SwapFree_bytes / node_memory_SwapTotal_bytes > 0.5'';
                for = "30m";
                labels.severity = "warning";
                annotations.summary = "Over half of swap in use on {{ $labels.instance }}";
              }
              {
                alert = "HostOomKill";
                expr = ''increase(node_vmstat_oom_kill[1h]) > 0'';
                labels.severity = "warning";
                annotations.summary = "OOM killer ran on {{ $labels.instance }} in the last hour";
              }
            ];
          }
          {
            name = "backups";
            rules = [
              {
                # Immediate notice; SystemdUnitFailed skips oneshots.
                alert = "BackupFailed";
                expr = ''node_systemd_unit_state{name="rclone-b2-backup.service",state="failed"} == 1'';
                for = "2m";
                labels.severity = "critical";
                annotations.summary = "B2 backup unit failed on {{ $labels.instance }}";
              }
              {
                # The daily run can take hours, and TimeoutStartSec=infinity means
                # a hung run never fails, so catch staleness as well as failure.
                # The timestamp is written by ExecStartPost in modules/nas.nix.
                alert = "BackupStale";
                expr = ''time() - rclone_b2_backup_last_success_timestamp_seconds > 26 * 3600'';
                for = "10m";
                labels.severity = "critical";
                annotations.summary = "No successful B2 backup in the last 26h on {{ $labels.instance }}";
              }
              {
                # No marker at all: the first run after this deploy has not
                # succeeded yet, or the textfile was lost.
                alert = "BackupNeverSucceeded";
                expr = ''absent(rclone_b2_backup_last_success_timestamp_seconds)'';
                for = "26h";
                labels.severity = "critical";
                annotations.summary = "B2 backup has written no success marker for 26h";
              }
            ];
          }
        ];
      })
    ];
  };

  # Email delivery for the rules above. The NixOS module runs envsubst over
  # the generated config, so $SMTP_PASSWORD comes from sops at service start
  # (alertmanager itself has no password-file option).
  services.prometheus.alertmanager = {
    enable = true;
    listenAddress = "127.0.0.1";

    configuration = {
      global = {
        resolve_timeout = "5m";
        smtp_smarthost = "smtp.fastmail.com:587";
        smtp_from = "chris@mcneill.fyi";
        smtp_auth_username = "chris@mcneill.fyi";
        # Read from the service's systemd credentials directory; no secret is
        # ever interpolated into alertmanager.yml or an EnvironmentFile.
        smtp_auth_password_file = "/run/credentials/alertmanager.service/smtp_password";
        smtp_require_tls = true;
      };

      route = {
        receiver = "email";
        group_by = [ "alertname" "instance" "job" ];
        group_wait = "30s";
        group_interval = "5m";
        repeat_interval = "4h";
        routes = [
          {
            # Critical alerts repeat hourly instead of every four hours.
            matchers = [ "severity=critical" ];
            receiver = "email";
            repeat_interval = "1h";
          }
        ];
      };

      receivers = [
        {
          name = "email";
          email_configs = [
            {
              to = "chris@mcneill.fyi";
              send_resolved = true;
            }
          ];
        }
      ];
    };
  };

  # Feed the SMTP password to Alertmanager as a systemd credential. The unit
  # runs as a DynamicUser, which cannot read the root-only sops file directly.
  systemd.services.alertmanager.serviceConfig.LoadCredential = [
    "smtp_password:${config.sops.secrets.smtp_password.path}"
  ];

  # Nested user namespaces (PrivateUsers=true) conflict with nspawn's bind-mounted
  # /nix/store when ProtectSystem remounts the tree. why: docs/notes.md#container-one-offs
  systemd.services.prometheus.serviceConfig.PrivateUsers = lib.mkForce false;

  # Centralized journal receiver: every host and container pushes here via
  # systemd-journal-upload over LAN HTTP. Query with `fleet-logs` or
  # `journalctl -D /var/log/journal/remote`.
  services.journald.remote = {
    enable = true;
    listen = "http";
    port = 19532;
    settings.Remote = {
      SplitMode = "host";
      MaxUse = "4G";
      KeepFree = "2G";
    };
  };

  # Upstream unit sets PrivateNetwork=yes (assuming socket activation needs no
  # network), which fails with 225/NETWORK inside nspawn.
  systemd.services.systemd-journal-remote.serviceConfig.PrivateNetwork = false;

  # Let deploy inspect `/var/log/journal/remote` without sudo.
  users.users.deploy.extraGroups = [ "systemd-journal" "systemd-journal-remote" ];

  environment.systemPackages = [ fleetLogs ];
}
