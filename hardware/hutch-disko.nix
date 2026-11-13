# hutch baremetal boot-drive layout. No LUKS/TPM — plain btrfs with
# subvolumes (./disko-layout.nix). Only the boot drive is managed here; the
# two 8TB ZFS disks are imported in place by modules/nas.nix, NOT formatted
# by disko.
#
# ⚠ VERIFY the device with `lsblk` before running disko: with the 8TB HDDs
# installed they may claim /dev/sd*, and the boot drive could be NVMe
# (/dev/nvme0n1) or SATA. Getting this wrong wipes a data disk.
import ./disko-layout.nix { swapSize = "64G"; }
