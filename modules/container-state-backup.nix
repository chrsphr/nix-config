{ config, pkgs, lib, ... }:

# Offsite backup of container *state* on hutch, to the encrypted B2 remote.
#
# Opt-in: only containers listed in `containers` below are backed up. To add
# one, add an entry with the paths to copy (`include`, relative to the container
# root) and any rclone filters to skip (`exclude`, caches and regenerable data).
#
# Source is the newest read-only snapshot from container-snapshots.nix, so the
# copy is consistent. Copies land at b2crypt:containers/<container>/<path>.

let
  containers = {
    sonarr = {
      include = [ "var/lib/sonarr" "var/lib/private/prowlarr" ];
      exclude = [ "**/Backups/**" ];  # Sonarr's scheduled backup zips
    };
    radarr = {
      include = [ "var/lib/radarr" ];
      exclude = [ "**/Backups/**" ];  # Radarr's scheduled backup zips
    };
    immich = {
      include = [ "var/lib/postgresql" ];  # the database; photos are in Media/Photos
      exclude = [ ];
    };
  };

  snapRoot = "/snapshots/containers";

  # One rclone sync per include path, from the newest snapshot. A container with
  # no snapshot is skipped and the run fails so it gets noticed.
  syncFor = name: spec: lib.concatMapStrings (inc: ''
    snap=$(ls -1d ${snapRoot}/${name}/2* 2>/dev/null | tail -n 1 || true)
    if [ -z "$snap" ]; then
      echo "NO SNAPSHOT: ${name}" >&2
      failed="$failed ${name}"
    else
      echo "==> ${name}: $snap/${inc} -> b2crypt:containers/${name}/${inc}"
      ${pkgs.rclone}/bin/rclone \
        --config ${config.sops.templates."rclone.conf".path} \
        sync "$snap/${inc}" ${lib.escapeShellArg "b2crypt:containers/${name}/${inc}"} \
        --fast-list \
        --b2-chunk-size 96M \
        --transfers 8 \
        --checkers 16 \
        --retries 3 \
        --low-level-retries 10 \
        --stats-one-line \
        --stats 5m \
        ${lib.concatStringsSep " " (map (e: "--exclude ${lib.escapeShellArg e}") spec.exclude)} \
        || failed="$failed ${name}/${inc}"
    fi
  '') spec.include;
in
{
  systemd.services.container-state-backup = {
    description = "Encrypted offsite copy of container state (hutch) to Backblaze B2";
    after = [ "network-online.target" "sops-nix.service" "container-snapshot.service" ];
    wants = [ "network-online.target" ];
    requires = [ "zfs-mount.service" ];

    # Same guard as the media job: no pool, no backup.
    unitConfig.ConditionPathIsMountPoint = "/mnt/Hutch/Media";

    serviceConfig = {
      Type = "oneshot";
      TimeoutStartSec = "infinity";
      Nice = 10;
      IOSchedulingClass = "idle";
    };

    path = [ pkgs.coreutils ];

    script = ''
      failed=""
    '' + lib.concatStrings (lib.mapAttrsToList syncFor containers) + ''
      if [ -n "$failed" ]; then
        echo "FAILED:$failed" >&2
        exit 1
      fi
    '';
  };

  systemd.timers.container-state-backup = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      # After the 03:00 snapshot, so the newest snapshot is tonight's.
      OnCalendar = "*-*-* 04:00:00";
      Persistent = true;
      RandomizedDelaySec = "20m";
    };
  };
}
