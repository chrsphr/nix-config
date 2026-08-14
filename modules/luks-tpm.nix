{ config, pkgs, lib, ... }:

# LUKS root with TPM2 auto-unlock. Assumes the disko layout in
# hardware/*-disko.nix (partition labelled "luks", opened as cryptroot).
# runbook: docs/framework-install.md §7 (TPM enrolment)
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
