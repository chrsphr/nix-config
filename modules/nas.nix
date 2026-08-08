{ config, pkgs, lib, ... }:

# The NAS role: ZFS pool, NFS exports, snapshots and B2 sync. Imported by
# hutch, which owns storage and containers on one box.
#
# Took over from the TrueNAS "lilnas" VM (retired 2026-08-08). The two 8TB
# disks moved into the hutch chassis and pool "Hutch" was imported in place —
# never reformatted — so dataset properties and snapshots came with it. The
# settings below were derived from TrueNAS's config export; the "TrueNAS: ..."
# notes record what each one is reproducing.

let
  keys = import ./keys.nix;
in
{
  # ---------------------------------------------------------------------------
  # ZFS: import the existing pool, don't create anything.
  # Pool "Hutch" (guid 5739333095810664970), 2x 8TB drives.
  # Datasets (Hutch/Media, Hutch/Backups, ...) mount themselves via their
  # own mountpoint properties under /mnt/Hutch/. If an import ever fails, the
  # media containers' mount guard (see hosts/hutch.nix) keeps them from
  # starting against an empty library.
  # ---------------------------------------------------------------------------
  networking.hostId = "a8f3c1d2";  # Required by ZFS. Arbitrary but must not change.
  boot.supportedFilesystems = [ "zfs" ];
  boot.zfs.extraPools = [ "Hutch" ];
  # Needed once, because the pool was last imported by TrueNAS under a
  # different hostId. Now that hutch has imported it cleanly these can go —
  # they bypass ZFS's multi-host safety checks, so don't leave them on
  # indefinitely.
  # TODO: drop both after confirming a clean boot without them.
  boot.zfs.forceImportAll = true;
  boot.zfs.forceImportRoot = true;

  # TrueNAS scrub: Sunday 00:00, threshold 35 days (i.e. ~monthly).
  services.zfs.autoScrub = {
    enable = true;
    interval = "monthly";
  };
  services.zfs.trim.enable = true;

  # TrueNAS periodic snapshot task: Hutch/Media (non-recursive), daily at
  # midnight, 2-week retention, naming schema auto-%Y-%m-%d_%H-%M.
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

  # ---------------------------------------------------------------------------
  # NFS (TrueNAS: service enabled, NFSv3+NFSv4, no network restrictions).
  # /mnt/Hutch/Media   — mapall chrsphr:root (all clients squashed to uid 3000)
  # /mnt/Hutch/Backups — no squash mapping
  # 192.168.0.0/16 because chris-framework mounts over WiFi from 192.168.4.x.
  # ---------------------------------------------------------------------------
  services.nfs.server = {
    enable = true;
    exports = ''
      /mnt/Hutch/Media   192.168.0.0/16(rw,all_squash,anonuid=3000,anongid=0,sync,no_subtree_check)
      /mnt/Hutch/Backups 192.168.0.0/16(rw,sync,no_subtree_check)
    '';
  };
  networking.firewall.allowedTCPPorts = [ 2049 111 ];
  networking.firewall.allowedUDPPorts = [ 2049 111 ];

  # ---------------------------------------------------------------------------
  # SMB. TrueNAS had shares defined (netbios HUTCH, workgroup WORKGROUP) but
  # the CIFS service itself was DISABLED — only nfs+ssh were enabled.
  # Included here for parity; flip enable to true if you actually use SMB.
  # ---------------------------------------------------------------------------
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

  # ---------------------------------------------------------------------------
  # Cloud sync to Backblaze B2 (TrueNAS cloudsync tasks, both PUSH/COPY):
  #   Photos Backup:   /mnt/Hutch/Media/Photos -> B2 Hutch-Backup/images, Wed 00:00
  #   VM Image Backup: /mnt/Hutch/Backups      -> B2 Hutch-Backup/backups, Tue 00:00
  # COPY mode => plain `rclone copy` (never deletes at the destination).
  #
  # The B2 application key is NOT in this repo — write it by hand at
  # /var/lib/rclone/rclone.conf (mode 0600) with:
  #   [b2]
  #   type = b2
  #   account = <B2 keyID>
  #   key = <B2 applicationKey>
  # TODO: move to sops once hutch has its own age key enrolled in .sops.yaml.
  # ---------------------------------------------------------------------------
  systemd.tmpfiles.rules = [
    "d /var/lib/rclone 0700 root root -"
  ];

  systemd.services.rclone-photos-backup = {
    description = "Sync Photos to B2 Hutch-Backup/images";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.rclone}/bin/rclone --config /var/lib/rclone/rclone.conf copy /mnt/Hutch/Media/Photos b2:Hutch-Backup/images --fast-list --b2-chunk-size 96M";
    };
  };
  systemd.timers.rclone-photos-backup = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "Wed *-*-* 00:00:00";
      Persistent = true;
    };
  };

  systemd.services.rclone-backups-backup = {
    description = "Sync Backups to B2 Hutch-Backup/backups";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.rclone}/bin/rclone --config /var/lib/rclone/rclone.conf copy /mnt/Hutch/Backups b2:Hutch-Backup/backups --fast-list --b2-chunk-size 96M";
    };
  };
  systemd.timers.rclone-backups-backup = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "Tue *-*-* 00:00:00";
      Persistent = true;
    };
  };

  # ---------------------------------------------------------------------------
  # TrueNAS cron jobs / init scripts:
  #   powertop --auto-tune (daily + postinit)   -> powerManagement.powertop
  #   powersave CPU governor (postinit)         -> powerManagement.cpuFreqGovernor
  #   SMART short (Wed 00:00) / long (1st 04:00)-> services.smartd below
  # ---------------------------------------------------------------------------
  powerManagement.powertop.enable = true;
  powerManagement.cpuFreqGovernor = "powersave";

  # ---------------------------------------------------------------------------
  # Further idle/load tuning, NOT inherited from TrueNAS. hutch is an i5-12600K
  # (Alder Lake) doing NAS work, so the stock desktop power envelope is far
  # more than it ever needs.
  #
  # Checked and deliberately skipped:
  #   - RAPL package power limits (PL1 135W / PL2 150W): left at stock on
  #     purpose. Don't cap these.
  #   - powerManagement.scsiLinkPolicy: both 8TB drives are on host4/host5,
  #     already at med_power_with_dipm. Only the empty ports sit at
  #     keep_firmware_settings, so forcing ALPM globally buys nothing.
  #   - HDD spindown (hdparm -B/-S): plex/sonarr/transmission/sanoid touch the
  #     Media dataset continuously — the drives would thrash, not idle.
  # ---------------------------------------------------------------------------

  # Alder Lake's hybrid P/E topology; Intel's own daemon handles it better
  # than the kernel's passive thermal throttling alone.
  services.thermald.enable = true;

  # EPP is the one knob cpuFreqGovernor="powersave" does NOT set: under
  # intel_pstate's active mode the governor picks the *algorithm*, while EPP
  # biases it within that. Stock is balance_performance; balance_power is a
  # measurable idle/light-load saving with no impact on this workload.
  #
  # Ordered after powertop so auto-tune can't clobber it. Non-fatal by design:
  # the file is absent unless intel_pstate is in active mode with HWP.
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
      # Match by WWN — stable per-drive regardless of how udev formats the
      # by-id name (on this kernel it's ata-HUH728080ALE601_<SERIAL>, not
      # ata-<SERIAL>; device letters can also move). Verify with `ls -l
      # /dev/disk/by-id/wwn-*`.
      # -d sat: smartd can't auto-detect the device type on hutch's
      # controller ("unable to autodetect device type"), but explicit SATA
      # passthrough works — verified with `smartctl -d sat -i/-H`.
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

  # ---------------------------------------------------------------------------
  # Users from TrueNAS (UIDs preserved so NFS ownership survives the move):
  #   chrsphr uid=3000 (home was /mnt/Hutch/Chris)
  #   hutch   uid=3001 (nologin; used for file ownership)
  #   admin   uid=950  -> skipped, NixOS root covers it
  # ---------------------------------------------------------------------------
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
