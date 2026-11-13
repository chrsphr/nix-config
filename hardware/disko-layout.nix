# Shared boot-drive layout: GPT, ESP, btrfs subvolumes with a swapfile.
# Called by the per-host hardware/<name>-disko.nix files, which stay as plain
# attrsets so `disko ./hardware/<name>-disko.nix` keeps working (install docs).
#
#   luks = true   personal machines: LUKS2 + TPM2 unlock (modules/luks-tpm.nix
#                 expects the "luks" partition label / "cryptroot" name), a
#                 /home subvolume, discard=async and a 1G ESP.
#   luks = false  servers: plain btrfs, no /home, 512M ESP.
#
# ⚠ VERIFY `device` with `lsblk` before running disko — getting it wrong wipes
# the wrong disk (on hutch the 8TB ZFS disks sit next to the boot drive).
{ swapSize, luks ? false, device ? "/dev/nvme0n1" }:

let
  mount = compress:
    [ compress "noatime" ] ++ (if luks then [ "discard=async" ] else [ ]);
  subvol = mountpoint: {
    inherit mountpoint;
    mountOptions = mount "compress=zstd:1";
  };

  btrfs = {
    type = "btrfs";
    extraArgs = [ "-L" "nixos" "-f" ];
    subvolumes = {
      "/root" = subvol "/";
      "/nix" = {
        mountpoint = "/nix";
        # compress-force overrides btrfs's heuristic — store ELFs/scripts
        # always compress well, but the heuristic occasionally skips them.
        mountOptions = mount "compress-force=zstd:1";
      };
      "/persist" = subvol "/persist";
      # Target for modules/container-snapshots.nix on the servers.
      "/snapshots" = subvol "/snapshots";
      "/swap" = {
        mountpoint = "/swap";
        swap.swapfile.size = swapSize;
      };
    } // (if luks then { "/home" = subvol "/home"; } else { });
  };
in
{
  disko.devices.disk.main = {
    type = "disk";
    inherit device;
    content = {
      type = "gpt";
      partitions = {
        ESP = {
          priority = 1;
          size = if luks then "1G" else "512M";
          type = "EF00";
          content = {
            type = "filesystem";
            format = "vfat";
            mountpoint = "/boot";
            mountOptions = [ "umask=0077" ];
          };
        };
      } // (if luks then {
        luks = {
          size = "100%";
          label = "luks";
          content = {
            type = "luks";
            name = "cryptroot";
            extraOpenArgs = [ "--allow-discards" ];
            settings = {
              allowDiscards = true;
              crypttabExtraOpts = [ "tpm2-device=auto" ];
            };
            content = btrfs;
          };
        };
      } else {
        root = {
          size = "100%";
          content = btrfs;
        };
      });
    };
  };
}
