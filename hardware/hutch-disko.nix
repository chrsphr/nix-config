{
  # hutch baremetal boot-drive layout. No LUKS/TPM — plain btrfs with
  # subvolumes. Only the boot drive is managed here; the two 8TB ZFS disks
  # are imported in place by modules/nas.nix, NOT formatted by disko.
  #
  # ⚠ VERIFY the device with `lsblk` before running disko: with the 8TB HDDs
  # installed they may claim /dev/sd*, and the boot drive could be NVMe
  # (/dev/nvme0n1) or SATA. Getting this wrong wipes a data disk.
  disko.devices.disk.main = {
    type = "disk";
    device = "/dev/nvme0n1";
    content = {
      type = "gpt";
      partitions = {
        ESP = {
          priority = 1;
          size = "512M";
          type = "EF00";
          content = {
            type = "filesystem";
            format = "vfat";
            mountpoint = "/boot";
            mountOptions = [ "umask=0077" ];
          };
        };
        root = {
          size = "100%";
          content = {
            type = "btrfs";
            extraArgs = [ "-L" "nixos" "-f" ];
            subvolumes = {
              "/root" = {
                mountpoint = "/";
                mountOptions = [ "compress=zstd:1" "noatime" ];
              };
              "/nix" = {
                mountpoint = "/nix";
                # compress-force overrides btrfs's heuristic — store ELFs/scripts
                # always compress well, but the heuristic occasionally skips them.
                mountOptions = [ "compress-force=zstd:1" "noatime" ];
              };
              "/persist" = {
                mountpoint = "/persist";
                mountOptions = [ "compress=zstd:1" "noatime" ];
              };
              "/snapshots" = {
                mountpoint = "/snapshots";
                mountOptions = [ "compress=zstd:1" "noatime" ];
              };
              "/swap" = {
                mountpoint = "/swap";
                swap.swapfile.size = "4G";
              };
            };
          };
        };
      };
    };
  };
}
