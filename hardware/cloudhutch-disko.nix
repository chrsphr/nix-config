{
  # cloudhutch boot-drive layout. Single virtio disk, no LUKS/TPM — a cloud
  # VPS has no physical console and the provider owns the hypervisor.
  #
  # netcup presents the disk as /dev/vda. If their panel/`lsblk` shows /dev/sda
  # instead, change `device` before running disko.
  #
  # Swap is 4G; adjust if the VPS RAM changes.
  disko.devices.disk.main = {
    type = "disk";
    device = "/dev/vda";
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
                # compress-force overrides btrfs's heuristic — store ELFs and
                # scripts always compress well.
                mountOptions = [ "compress-force=zstd:1" "noatime" ];
              };
              "/persist" = {
                mountpoint = "/persist";
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
