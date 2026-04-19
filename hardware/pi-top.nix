{ config, lib, pkgs, modulesPath, ... }:

{
  imports = [
    (modulesPath + "/installer/scan/not-detected.nix")
  ];

  boot.initrd.availableKernelModules = [ "xhci_pci" "usbhid" ];
  boot.initrd.kernelModules = [ ];
  boot.kernelModules = [ ];
  boot.extraModulePackages = [ ];

  fileSystems."/" = {
    device = "/dev/disk/by-uuid/2d1a2006-26a6-4421-9853-ec1a75cc410a";
    fsType = "ext4";
  };

  fileSystems."/boot/firmware" = {
    device = "/dev/disk/by-uuid/AF9C-5C8D";
    fsType = "vfat";
  };

  swapDevices = [ ];

  nixpkgs.hostPlatform = lib.mkDefault "aarch64-linux";
}
