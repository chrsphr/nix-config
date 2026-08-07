{ ... }:

# Baremetal hardware bits for hutch. Common SATA/NVMe/USB initrd modules so
# the boot disk shows up regardless of controller — refine from
# `nixos-generate-config` output on the actual box if anything's missing.
{
  boot.initrd.availableKernelModules = [ "ahci" "nvme" "xhci_pci" "usbhid" "usb_storage" "sd_mod" ];
}
