# minihutch baremetal hardware.
#
# ⚠ PLACEHOLDER — regenerate on the box before the first real deploy:
#     nixos-generate-config --no-filesystems --root /mnt
#   then copy the boot.initrd.availableKernelModules / boot.kernelModules /
#   hardware.cpu.* lines it produces over the ones below. The values here are
#   copied from hutch (Intel, NVMe + AHCI) and are a reasonable first boot for
#   a similar box, but they are NOT scanned from this machine.
#
# `--no-filesystems` matters: the boot drive layout is owned by
# hardware/minihutch-disko.nix, and a generated fileSystems block would
# collide with it.
{ config, lib, pkgs, modulesPath, ... }:

{
  imports =
    [ (modulesPath + "/installer/scan/not-detected.nix")
    ];

  boot.initrd.availableKernelModules = [ "xhci_pci" "ahci" "nvme" "usbhid" "usb_storage" "sd_mod" ];
  boot.initrd.kernelModules = [ ];
  boot.kernelModules = [ "kvm-intel" ];
  boot.extraModulePackages = [ ];

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
}
