{
  # minihutch boot-drive layout. Same shape as hutch (hardware/hutch-disko.nix):
  # no LUKS/TPM, plain btrfs with subvolumes. minihutch has no data pool — this
  # is the only disk it owns.
  #
  # Verified on the live ISO 2026-08-09: /dev/nvme0n1 is a 931.5G Crucial
  # CT1000P310SSD2 (serial 2423499DAAAA), the only internal disk. It previously
  # held minimox's Proxmox ZFS root (pool "rpool", 6 LXC subvolumes); that was
  # wiped deliberately at install.
  #
  # Swap sized to this box's 8G of RAM (Intel N100), not hutch's 64G.
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
                swap.swapfile.size = "16G";
              };
            };
          };
        };
      };
    };
  };
}
