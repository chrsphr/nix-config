{
  # hutch-test VM disk layout. This is a test VM, so no LUKS/TPM — plain btrfs
  # with subvolumes. Verify the device with `lsblk` before running disko.
  disko.devices.disk.main = {
    type = "disk";
    device = "/dev/sda";
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
