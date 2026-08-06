{ config, pkgs, lib, ... }:

# The NAS role: replaces the TrueNAS "lilnas" VM (192.168.1.12).
# Imported by hutch-test, which takes over storage + containers on one host.
# Source: lilnas-25.10.5-20260806203849.db (TrueNAS config export).
#
# Migration model: pass the two 8TB disks (serials VKHWUELX, VKHNN8PX) through
# to the hutch-test VM in Proxmox and import the existing pool "Hutch" in
# place — no reformatting; dataset properties and snapshots travel with the
# pool.
#
# Still needed before cutover:
#   - Attach the disks to the VM (Proxmox: qm set 102 --scsi1 /dev/disk/by-id/...)
#   - Write /var/lib/rclone/rclone.conf with a "b2" remote (see rclone section)
#   - Verify pool vdev layout on TrueNAS (zpool status) — expected mirror
#   - Repoint NFS clients (desktop fstab, modules/nfs-home-automount.nix use
#     192.168.1.12) — or add 192.168.1.12 as a secondary IP on br0 here

let
  keys = import ./keys.nix;
in
{
  # ---------------------------------------------------------------------------
  # ZFS: import the existing pool, don't create anything.
  # TrueNAS: pool "Hutch" (guid 5739333095810664970), 2x 8TB drives.
  # Datasets (Hutch/Media, Hutch/Backups, ...) mount themselves via their
  # own mountpoint properties under /mnt/Hutch/.
  # Until the disks are attached, zfs-import-Hutch will fail at boot — the
  # system still boots, and the immich container's mount guard (see
  # hosts/hutch-test.nix) keeps it from starting against an empty library.
  # ---------------------------------------------------------------------------
  networking.hostId = "a8f3c1d2";  # Required by ZFS. Arbitrary; must differ from TrueNAS's.
  boot.supportedFilesystems = [ "zfs" ];
  boot.zfs.extraPools = [ "Hutch" ];
  # The pool was last imported by TrueNAS (different hostId) — force the first
  # import. Both flags can be dropped after the first successful boot.
  # forceImportRoot is a no-op here (root fs is ext4, no ZFS root pool) but
  # the module requires it alongside forceImportAll.
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
  # The B2 application key lives in the TrueNAS config DB (system_cloudcredentials,
  # encrypted) and is NOT portable — write a fresh config at
  # /var/lib/rclone/rclone.conf (mode 0600) with:
  #   [b2]
  #   type = b2
  #   account = <B2 keyID>
  #   key = <B2 applicationKey>
  # TODO: move to sops once hutch-test has its own age key enrolled in .sops.yaml.
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

  services.smartd = {
    enable = true;
    devices = [
      # Match by serial — device letters change when disks move between VMs.
      # Verify the by-id names after attaching the disks to the VM; whether
      # SMART data passes through depends on the Proxmox disk attachment type.
      {
        device = "/dev/disk/by-id/ata-VKHWUELX";  # 8TB
        options = "-a -s (S/../../3/00|L/../01/./04)";
      }
      {
        device = "/dev/disk/by-id/ata-VKHNN8PX";  # 8TB
        options = "-a -s (S/../../3/00|L/../01/./04)";
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

  environment.systemPackages = with pkgs; [ rclone smartmontools ];
}
