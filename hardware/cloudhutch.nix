# cloudhutch hardware: netcup x86_64 KVM VPS.
#
# Generic QEMU/virtio guest baseline rather than a scanned config — there is
# no physical hardware to discover, and netcup's disk/NIC are virtio. The disk
# layout is owned by hardware/cloudhutch-disko.nix; there is deliberately no
# fileSystems block here.
{ lib, modulesPath, ... }:

{
  imports = [
    (modulesPath + "/profiles/qemu-guest.nix")
  ];

  # Keep the platform explicit so a direct nixos-rebuild on the box cannot
  # drift to another architecture.
  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
}
