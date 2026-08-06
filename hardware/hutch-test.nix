{ ... }:

# Proxmox VM hardware bits. The VirtIO disk drivers must be in the initrd or
# boot hangs on "a start job is running for /dev/disk/by-partlabel/disk-main-root"
# (kernel can't see /dev/vda, so the root partition never appears).
{
  boot.initrd.availableKernelModules = [ "virtio_pci" "virtio_blk" "virtio_scsi" ];
}
