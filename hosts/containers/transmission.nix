{ config, pkgs, lib, ... }:

# Transmission as a NixOS container on hutch. The Media dataset is bind
# mounted at /mnt/media (hosts/hutch.nix).

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

  # The module's chroot sandbox can't be set up inside nspawn (226/NAMESPACE);
  # the container is the isolation boundary. why: docs/notes.md#container-one-offs
  systemd.services.transmission.serviceConfig = {
    RootDirectory = lib.mkForce "";
    RootDirectoryStartOnly = lib.mkForce false;
    MountAPIVFS = lib.mkForce false;
    BindPaths = lib.mkForce [];
    BindReadOnlyPaths = lib.mkForce [];
  };
}
