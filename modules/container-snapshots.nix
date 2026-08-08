{ config, pkgs, lib, ... }:

# btrfs subvolumes + nightly crash-consistent snapshots for the NixOS
# (systemd-nspawn) containers on hutch.
#
# Container roots live at /var/lib/nixos-containers/<name> inside the btrfs
# /root subvolume. Two pieces:
#
#   1. systemd.tmpfiles `v` rules — declare each container root as a btrfs
#      subvolume. Type `v` creates a subvolume if the path doesn't exist
#      (on btrfs; plain dir elsewhere) and does nothing if it already does,
#      so this is idempotent desired-state, not a mutation script.
#      systemd-tmpfiles-setup.service runs Before=sysinit.target, while
#      containers start via machines.target -> multi-user.target, so the
#      subvolumes exist before any container ever starts — including first
#      boot. Containers added to lib/network.nix later get theirs at the
#      next boot (or `sudo systemd-tmpfiles --create`) with no config here.
#      The nixos-containers preStart only does `mkdir -p` on the root (a
#      no-op afterwards), and container@.service already carries
#      RequiresMountsFor=/var/lib/nixos-containers/%i.
#
#   2. container-snapshot.{service,timer} — nightly read-only snapshot of
#      each container subvolume into /snapshots/containers/<name>/, keeping
#      the newest 14 (mirrors the sanoid daily=14 retention on Hutch/Media).
#      Snapshots are atomic COW => crash-consistent, like a power cut:
#      sqlite (gatus) and postgres (immich) both recover from that on start.
#      No container downtime.
#
# Scope notes:
#   - Media (Photos/Movies/TV) is NOT in the container roots — it's
#     bind-mounted from the ZFS pool and already covered by sanoid + the
#     encrypted rclone→B2 mirror (modules/nas.nix).
#   - /var/lib/sops-nix/<name> (host-side keys bind-mounted into containers)
#     is tiny but NOT captured by these snapshots — fold it in when an
#     off-disk transport is added.
#   - Snapshots sit on the same NVMe as the live roots: this is rollback,
#     not backup. Off-disk copy (→ /mnt/Hutch/Backups → B2) is a follow-up.

let
  containerNames = builtins.attrNames config.containers;
  keep = 14;
in
lib.mkIf (containerNames != []) {
  systemd.tmpfiles.rules =
    [ "d /var/lib/nixos-containers 0755 root root -" ]
    ++ map (n: "v /var/lib/nixos-containers/${n} 0755 root root -") containerNames;

  systemd.services.container-snapshot = {
    description = "Snapshot NixOS container root subvolumes (read-only)";
    path = [ pkgs.btrfs-progs pkgs.coreutils ];
    serviceConfig.Type = "oneshot";
    script = ''
      set -euo pipefail
      for name in ${lib.concatStringsSep " " containerNames}; do
        root="/var/lib/nixos-containers/$name"
        dest="/snapshots/containers/$name"
        # Skip rather than fail the run if the root isn't a subvolume yet
        # (e.g. first boot ordering, or a container declared but never started).
        btrfs subvolume show "$root" >/dev/null 2>&1 || continue
        mkdir -p "$dest"
        btrfs subvolume snapshot -r "$root" "$dest/$(date +%Y-%m-%d_%H%M)"
        # Prune to the newest ${toString keep} snapshots.
        ls -1d "$dest"/2* | sort | head -n -${toString keep} | \
          while read -r snap; do
            btrfs subvolume delete "$snap"
          done
      done
    '';
  };

  # 03:00: after sanoid's midnight ZFS snapshots. The rclone→B2 backup starts
  # at 01:00 and can run for hours, so these do overlap — that's fine, they
  # touch different disks (NVMe container roots vs the ZFS pool).
  # Persistent so a missed run fires at next boot.
  systemd.timers.container-snapshot = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "*-*-* 03:00:00";
      Persistent = true;
    };
  };
}
