{ config, pkgs, lib, ... }:

# LUKS root with TPM2 auto-unlock.
#
# Assumes the disko layout in hardware/*-disko.nix: a single LUKS
# partition labelled "luks" containing the btrfs root, opened as
# /dev/mapper/cryptroot. Enrol TPM after install with:
#
#   sudo systemd-cryptenroll --tpm2-device=auto \
#     --tpm2-pcrs=0+2+7 /dev/disk/by-partlabel/luks
#
# (drop PCR 7 if Secure Boot is off — see docs/framework-install.md.)
{
  boot.initrd.systemd.enable = true;
  boot.initrd.systemd.tpm2.enable = true;
  boot.initrd.luks.devices.cryptroot = {
    device = "/dev/disk/by-partlabel/luks";
    allowDiscards = true;
    crypttabExtraOpts = [ "tpm2-device=auto" ];
  };
  security.tpm2.enable = true;
  environment.systemPackages = [ pkgs.tpm2-tools ];
}
