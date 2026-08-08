{ config, pkgs, lib, ... }:

# The NAS role: ZFS pool, NFS exports, snapshots and the encrypted B2 backup.
# Imported by hutch, which owns storage and containers on one box.
#
# Took over from the TrueNAS "lilnas" VM (retired 2026-08-08). The two 8TB
# disks moved into the hutch chassis and pool "Hutch" was imported in place —
# never reformatted — so dataset properties and snapshots came with it. The
# settings below were derived from TrueNAS's config export; the "TrueNAS: ..."
# notes record what each one is reproducing.

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
  # forceImportAll/forceImportRoot were needed for the first import only, when
  # the labels still carried TrueNAS's hostId. Both disks' labels now read
  # hostid a8f3c1d2 / hostname "hutch" (verified 2026-08-08 with zdb -l), so
  # a normal import succeeds and the multi-host safety checks are back on.
  # Don't reintroduce them: if an import ever fails, find out why first.
  #
  # forceImportRoot must be set explicitly — it still defaults to true here and
  # only flips to false in 26.11, so dropping the line would have left the
  # force-import in place while looking like it had been turned off.
  boot.zfs.forceImportRoot = false;

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
  # Encrypted offsite backup to Backblaze B2.
  #
  # Replaced the TrueNAS-era cloudsync tasks (plain `rclone copy` of Photos and
  # Backups, unencrypted, Tue/Wed 00:00). Three things changed:
  #
  #   1. Everything goes through an rclone `crypt` remote. File contents AND
  #      names/directories are encrypted locally; B2 stores opaque blobs under
  #      opaque paths and never sees the key.
  #   2. `sync`, not `copy` — the bucket mirrors current on-disk state instead
  #      of accumulating everything ever written. See the delete guards below.
  #   3. Credentials come from sops (secrets/hutch.yaml) rather than a
  #      hand-written /var/lib/rclone/rclone.conf.
  #
  # The crypt passwords are ALSO in 1Password ("backblaze hutchv2"). Losing both
  # them and secrets/hutch.yaml makes every byte in B2 permanently unreadable —
  # B2 cannot help, that is the point of client-side encryption.
  #
  # Bucket setup that is NOT expressed here (done by hand in the B2 console):
  #   - bucket `hutch-v2`, private, app key scoped to just that bucket
  #   - lifecycle: keepDaysAfterHide = 30, keepDaysAfterUpload = null
  # That lifecycle rule IS the undo window. Without it a bad sync is final.
  # Nothing in this file enforces either — check them if restores misbehave.
  # ---------------------------------------------------------------------------
  # hutch decrypts with its own SSH host key (sops.age.sshKeyPaths default), so
  # unlike the containers there is no key file to place at /var/secrets. The
  # default /run/secrets tmpfs is fine here: the host re-runs activation at boot.
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
    # network-online because rclone is useless without it; sops-nix because a
    # Persistent timer can fire at boot before the config template is rendered.
    after = [ "zfs-mount.service" "network-online.target" "sops-nix.service" ];
    wants = [ "network-online.target" ];
    requires = [ "zfs-mount.service" ];

    # If the pool did not import, /mnt/Hutch/Media is an empty directory on the
    # root filesystem — and `rclone sync` against empty sources would delete the
    # entire remote. Same guard the media containers use (hosts/hutch.nix).
    unitConfig.ConditionPathIsMountPoint = "/mnt/Hutch/Media";

    serviceConfig = {
      Type = "oneshot";
      # The first seed is ~4TB and runs for days; oneshot otherwise defaults to
      # a 90s start timeout and would be killed mid-transfer.
      TimeoutStartSec = "infinity";
      # Bulk background transfer — don't starve Plex of disk or CPU.
      Nice = 10;
      IOSchedulingClass = "idle";
    };

    # One path failing (transient B2 error, a --max-delete trip) must not skip
    # the remaining paths — NixOS job scripts run under `set -e`, so each rclone
    # is guarded and the unit reports failure only at the end.
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
      # A run in progress simply keeps the unit active, so a multi-day first
      # seed is safe: systemd will not start a second copy on top of it.
      Persistent = true;
      RandomizedDelaySec = "30m";
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
  #
  # Package C-states are capped at PC2 by HARDWARE, not config (verified
  # 2026-08-08 with turbostat/lspci): the 82599 10G NIC at 01:00.0 supports
  # only ASPM L0s, not L1, and ADL needs every PCIe link in L1 for PC3+.
  # Cores reach CC7, iGPU RC6 works, NVMe L1 is on, MSR 0xE2 is unlimited —
  # the NIC is the sole blocker, and it costs only ~1-2W at the package
  # (~2.7W RAPL idle as-is). Fix would be a NIC that supports L1; there is
  # no software knob. Don't re-investigate.
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
