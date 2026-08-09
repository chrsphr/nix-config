{
  # minihutch boot-drive layout. Same shape as hutch (hardware/hutch-disko.nix):
  # no LUKS/TPM, plain btrfs with subvolumes. minihutch has no data pool — this
  # is the only disk it owns.
  #
  # ⚠ VERIFY the device with `lsblk` before running disko. `/dev/nvme0n1` below
  # is a PLACEHOLDER copied from hutch; disko wipes whatever it points at.
  #
  # ⚠ The 64G swapfile is also inherited from hutch, which has 64G of RAM.
  # Size it to the actual RAM in this box before installing — the file is
  # created at install time and resizing it later means editing this AND
  # recreating /swap/swapfile by hand.
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
              # Target for modules/container-snapshots.nix.
              "/snapshots" = {
                mountpoint = "/snapshots";
                mountOptions = [ "compress=zstd:1" "noatime" ];
              };
              "/swap" = {
                mountpoint = "/swap";
                swap.swapfile.size = "64G";
              };
            };
          };
        };
      };
    };
  };
}
