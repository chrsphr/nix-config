{
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
                  # compress-force overrides btrfs's heuristic — store ELFs/scripts
                  # always compress well, but the heuristic occasionally skips them.
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
