{ config, pkgs, lib, ... }:

# btrfs subvolumes + nightly crash-consistent snapshots of the nspawn
# container roots, on both container hosts. Rollback, not backup: snapshots
# share the NVMe with the live roots. why: docs/notes.md#container-snapshot-design

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

  # 03:00, after sanoid's midnight snapshots; Persistent so a missed run
  # fires at next boot.
  systemd.timers.container-snapshot = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "*-*-* 03:00:00";
      Persistent = true;
    };
  };
}
