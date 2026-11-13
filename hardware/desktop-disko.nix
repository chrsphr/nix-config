# Desktop boot drive: LUKS2 + TPM2, btrfs subvolumes. Layout shared with
# the Framework — see ./disko-layout.nix.
# Verify the device with `lsblk` before running disko — getting this wrong
# wipes the wrong disk.
import ./disko-layout.nix { swapSize = "64G"; luks = true; }
