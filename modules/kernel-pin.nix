{ config, pkgs, lib, ... }:

# Shared kernel for both baremetal hosts: the newest kernel ZFS can build
# against, picked at eval time instead of a manual linuxPackages_X_Y pin.
# hutch needs the ZFS bound; minihutch has no ZFS but must run the SAME
# kernel because the usbip userspace is kernel-matched. May jump back and
# forth as kernels are added, removed, or (un)marked broken in nixpkgs.
# why: docs/notes.md#kernel-pin

let
  zfsCompatibleKernelPackages = lib.filterAttrs (
    name: kernelPackages:
    (builtins.match "linux_[0-9]+_[0-9]+" name) != null
    && (builtins.tryEval kernelPackages).success
    && (!kernelPackages.${config.boot.zfs.package.kernelModuleAttribute}.meta.broken)
  ) pkgs.linuxKernel.packages;
  latestZfsKernelPackage = lib.last (
    lib.sort (a: b: (lib.versionOlder a.kernel.version b.kernel.version)) (
      builtins.attrValues zfsCompatibleKernelPackages
    )
  );
in
{
  boot.kernelPackages = latestZfsKernelPackage;
}
