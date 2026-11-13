# minihutch boot-drive layout. Same shape as hutch: no LUKS/TPM, plain btrfs
# with subvolumes (./disko-layout.nix). minihutch has no data pool — this
# is the only disk it owns.
#
# Verified on the live ISO 2026-08-09: /dev/nvme0n1 is a 931.5G Crucial
# CT1000P310SSD2, the only internal disk. It previously held minimox's
# Proxmox ZFS root (pool "rpool", 6 LXC subvolumes); that was wiped
# deliberately at install.
#
# Swap sized to this box's 8G of RAM (Intel N100), not hutch's 64G.
import ./disko-layout.nix { swapSize = "16G"; }
