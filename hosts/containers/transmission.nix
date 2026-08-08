{ config, pkgs, lib, ... }:

# Transmission as a NixOS container on hutch. The Media dataset is bind
# mounted at /mnt/media (see hosts/hutch.nix).

{
  imports = [
    ./common.nix
  ];

  networking = {
    hostName = "transmission";
    firewall.allowedTCPPorts = [ 9091 ];
  };

  services.transmission = {
    enable = true;
    openFirewall = true;
    settings = {
      download-dir = "/mnt/media/Downloads";
      incomplete-dir = "/mnt/media/Downloads/.incomplete";
      incomplete-dir-enabled = true;
      rpc-bind-address = "0.0.0.0";
      rpc-whitelist-enabled = false;
      rpc-host-whitelist-enabled = false;
    };
  };

  # Allow transmission to write to the media bind mount
  users.users.transmission.extraGroups = [ "media" ];

  # The module's chroot sandbox (RootDirectory=/run/transmission +
  # MountAPIVFS) cannot be set up inside nspawn: MountAPIVFS makes systemd
  # stage /run/host/.os-release-stage/, but /run/host belongs to nspawn and
  # is read-only in the container — the unit dies with 226/NAMESPACE before
  # the daemon runs. Drop the chroot (and the bind mounts that exist only to
  # populate it); the container is the isolation boundary here anyway.
  systemd.services.transmission.serviceConfig = {
    RootDirectory = lib.mkForce "";
    RootDirectoryStartOnly = lib.mkForce false;
    MountAPIVFS = lib.mkForce false;
    BindPaths = lib.mkForce [];
    BindReadOnlyPaths = lib.mkForce [];
  };
}
