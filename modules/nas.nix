{ config, pkgs, lib, ... }:

# The NAS role: ZFS pool, NFS exports, snapshots and the encrypted B2 backup.
# Imported by hutch. Settings derive from the retired TrueNAS box's config
# export — history: docs/notes.md#truenas-takeover

let
  keys = import ./keys.nix;

  # What goes offsite, as <remote subdir> -> <local path>. Everything here is
  # mirrored, so adding a path costs B2 storage and removing one deletes it
  # from the remote on the next run (subject to the 30-day lifecycle window).
  backupPaths = {
    "TV"      = "/mnt/Hutch/Media/TV";
    "Movies"  = "/mnt/Hutch/Media/Movies";
    "Photos"  = "/mnt/Hutch/Media/Photos";
    "Sites"   = "/mnt/Hutch/Media/Sites";
    "Music"   = "/mnt/Hutch/Media/Music";
    "Backups" = "/mnt/Hutch/Backups";
  };
in
{
  # ZFS: import the existing pool "Hutch", don't create anything. Datasets
  # mount themselves via their own mountpoint properties under /mnt/Hutch/.
  networking.hostId = "a8f3c1d2";  # Required by ZFS. Arbitrary but must not change.
  boot.supportedFilesystems = [ "zfs" ];
  boot.zfs.extraPools = [ "Hutch" ];
  # Don't reintroduce forceImportAll/forceImportRoot; if an import fails, find
  # out why first. Must stay explicit until the 26.11 default flip.
  # why: docs/notes.md#forceimport-removal
  boot.zfs.forceImportRoot = false;

  # ARC reclaim tuning: an 8 GiB free-memory floor, deliberately not a cap.
  # why: docs/notes.md#zfs-arc
  boot.extraModprobeConfig = ''
    options zfs zfs_arc_sys_free=8589934592
  '';
  boot.kernel.sysctl."vm.swappiness" = 10;  # evict ARC before swapping services

  services.zfs.autoScrub = {
    enable = true;
    interval = "monthly";
  };
  services.zfs.trim.enable = true;

  # Daily snapshot of Hutch/Media at midnight, 14 kept.
  services.sanoid = {
    enable = true;
    interval = "*-*-* 00:00:00";
    datasets."Hutch/Media" = {
      autosnap = true;
      autoprune = true;
      daily = 14;
      hourly = 0;
      weekly = 0;
      monthly = 0;
      yearly = 0;
    };
  };

  # NFS: Media squashes all clients to uid 3000; Backups no squash.
  # /16 because chris-framework mounts over WiFi from 192.168.4.x.
  services.nfs.server = {
    enable = true;
    exports = ''
      /mnt/Hutch/Media   192.168.0.0/16(rw,all_squash,anonuid=3000,anongid=0,sync,no_subtree_check)
      /mnt/Hutch/Backups 192.168.0.0/16(rw,sync,no_subtree_check)
    '';
  };
  networking.firewall.allowedTCPPorts = [ 2049 111 ];
  networking.firewall.allowedUDPPorts = [ 2049 111 ];

  # Deliberately disabled, shares kept for parity. why: docs/notes.md#smb-dormant
  services.samba = {
    enable = false;
    settings = {
      global = {
        workgroup = "WORKGROUP";
        "server string" = "hutch";
        "netbios name" = "HUTCH";
        "map to guest" = "Never";
      };
      Media = {
        path = "/mnt/Hutch/Media";
        browseable = "yes";
        "read only" = "no";
      };
      Backups = {
        path = "/mnt/Hutch/Backups";
        browseable = "yes";
        "read only" = "no";
      };
    };
  };

  # Encrypted offsite mirror to Backblaze B2 via an rclone crypt remote.
  # Crypt passwords are escrowed in 1Password ("backblaze hutchv2") — losing
  # them AND secrets/hutch.yaml makes the bucket permanently unreadable.
  # Bucket lifecycle (the 30-day undo window) is hand-set in the B2 console.
  # why: docs/notes.md#b2-backup-design
  sops.defaultSopsFile = ../secrets/hutch.yaml;
  sops.secrets.b2_account = { };
  sops.secrets.b2_key = { };
  sops.secrets.rclone_crypt_password = { };
  sops.secrets.rclone_crypt_password2 = { };

  sops.templates."rclone.conf".content = ''
    [b2]
    type = b2
    account = ${config.sops.placeholder.b2_account}
    key = ${config.sops.placeholder.b2_key}
    # Soft-delete: removals become "hidden" versions, which is what lets the
    # bucket lifecycle rule hold them for 30 days. Do not set this to true.
    hard_delete = false

    [b2crypt]
    type = crypt
    remote = b2:hutch-v2
    filename_encryption = standard
    directory_name_encryption = true
    password = ${config.sops.placeholder.rclone_crypt_password}
    password2 = ${config.sops.placeholder.rclone_crypt_password2}
  '';

  systemd.services.rclone-b2-backup = {
    description = "Encrypted mirror of media + backups to Backblaze B2";
    after = [ "zfs-mount.service" "network-online.target" "sops-nix.service" ];
    wants = [ "network-online.target" ];
    requires = [ "zfs-mount.service" ];

    # Guard: syncing from an unmounted (empty) source would delete the remote.
    unitConfig.ConditionPathIsMountPoint = "/mnt/Hutch/Media";

    serviceConfig = {
      Type = "oneshot";
      TimeoutStartSec = "infinity";  # first seed runs for days
      # Bulk background transfer — don't starve Plex of disk or CPU.
      Nice = 10;
      IOSchedulingClass = "idle";
    };

    # Each rclone is guarded so one failing path doesn't skip the rest.
    script = ''
      failed=""
    '' + lib.concatStrings (lib.mapAttrsToList (dest: src: ''
      echo "==> ${src} -> b2crypt:${dest}"
      ${pkgs.rclone}/bin/rclone \
        --config ${config.sops.templates."rclone.conf".path} \
        sync ${lib.escapeShellArg src} b2crypt:${dest} \
        --fast-list \
        --b2-chunk-size 96M \
        --transfers 8 \
        --checkers 16 \
        --retries 3 \
        --low-level-retries 10 \
        --max-delete 1000 \
        --track-renames \
        --track-renames-strategy modtime,leaf \
        --stats 5m \
        --stats-one-line \
        || failed="$failed ${dest}"
    '') backupPaths) + ''
      if [ -n "$failed" ]; then
        echo "FAILED:$failed" >&2
        exit 1
      fi
    '';
  };

  systemd.timers.rclone-b2-backup = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "*-*-* 01:00:00";
      # A run in progress keeps the unit active; no second copy is started.
      Persistent = true;
      RandomizedDelaySec = "30m";
    };
  };

  powerManagement.powertop.enable = true;
  powerManagement.cpuFreqGovernor = "powersave";

  # Idle tuning is done: package C-states are hardware-capped at PC2 by the
  # 10G NIC — don't re-investigate. why: docs/notes.md#nas-power-tuning
  services.thermald.enable = true;

  # EPP balance_power; ordered after powertop so auto-tune can't clobber it.
  # why: docs/notes.md#thermald-and-smartd
  systemd.services.cpu-epp = {
    description = "Set CPU energy performance preference";
    wantedBy = [ "multi-user.target" ];
    after = [ "powertop.service" ];
    serviceConfig = { Type = "oneshot"; RemainAfterExit = true; };
    script = ''
      shopt -s nullglob
      for f in /sys/devices/system/cpu/cpufreq/policy*/energy_performance_preference; do
        echo balance_power > "$f" || echo "warn: could not write $f" >&2
      done
    '';
  };

  services.smartd = {
    enable = true;
    devices = [
      # WWN-matched (by-id names/letters move); -d sat because autodetect
      # fails on this controller. why: docs/notes.md#thermald-and-smartd
      {
        device = "/dev/disk/by-id/wwn-0x5000cca254dabd04";  # 8TB VKHWUELX
        options = "-d sat -a -s (S/../../3/00|L/../01/./04)";
      }
      {
        device = "/dev/disk/by-id/wwn-0x5000cca254d77b0e";  # 8TB VKHNN8PX
        options = "-d sat -a -s (S/../../3/00|L/../01/./04)";
      }
    ];
  };

  # UIDs preserved from TrueNAS so NFS ownership survives the move.
  users.groups.chrsphr.gid = 3000;
  users.groups.hutch.gid = 3001;
  users.users.chrsphr = {
    isNormalUser = true;
    uid = 3000;
    group = "chrsphr";
    home = "/mnt/Hutch/Chris";
    createHome = false;  # dataset comes with the pool
    shell = pkgs.bashInteractive;
    openssh.authorizedKeys.keys = [ keys.chris ];
  };
  users.users.hutch = {
    isSystemUser = true;
    uid = 3001;
    group = "hutch";
  };

  environment.systemPackages = with pkgs; [ rclone smartmontools powertop ];
}
