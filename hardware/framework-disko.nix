# Framework boot drive: LUKS2 + TPM2, btrfs subvolumes. Layout shared with
# the desktop — see ./disko-layout.nix.
import ./disko-layout.nix { swapSize = "64G"; luks = true; }
