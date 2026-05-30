{
  # Verify device with `lsblk` before running disko — getting this wrong wipes the wrong disk.
  disko.devices.disk.main = {
    type = "disk";
    device = "/dev/nvme0n1";
    content = {
      type = "gpt";
      partitions = {
        ESP = {
          priority = 1;
          size = "1G";
          type = "EF00";
          content = {
            type = "filesystem";
            format = "vfat";
            mountpoint = "/boot";
            mountOptions = [ "umask=0077" ];
          };
        };
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
            content = {
              type = "btrfs";
              extraArgs = [ "-L" "nixos" "-f" ];
              subvolumes = {
                "/root" = {
                  mountpoint = "/";
                  mountOptions = [ "compress=zstd:1" "noatime" "discard=async" ];
                };
                "/home" = {
                  mountpoint = "/home";
                  mountOptions = [ "compress=zstd:1" "noatime" "discard=async" ];
                };
                "/nix" = {
                  mountpoint = "/nix";
                  mountOptions = [ "compress-force=zstd:1" "noatime" "discard=async" ];
                };
                "/persist" = {
                  mountpoint = "/persist";
                  mountOptions = [ "compress=zstd:1" "noatime" "discard=async" ];
                };
                "/snapshots" = {
                  mountpoint = "/snapshots";
                  mountOptions = [ "compress=zstd:1" "noatime" "discard=async" ];
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
  };
}
