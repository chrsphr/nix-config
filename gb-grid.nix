{ config, pkgs, lib, gb-grid-pkg, ... }:

let
  hostsLib = import ./hosts.nix { inherit lib; };
  appHome = "/var/lib/gb-grid";
  dataDir = "${appHome}/data";
in
{
  imports = [ ./common.nix ];

  networking = hostsLib.mkStaticNetwork "gb-grid" // {
    hostName = "gb-grid";
  };

  environment.systemPackages = [
    gb-grid-pkg
    pkgs.duckdb
  ];

  users.users.gb-grid = {
    isSystemUser = true;
    group = "gb-grid";
    home = appHome;
    createHome = true;
  };
  users.groups.gb-grid = {};

  systemd.tmpfiles.rules = [
    "d ${appHome} 0750 gb-grid gb-grid -"
    "d ${dataDir} 0750 gb-grid gb-grid -"
  ];

  systemd.services.gb-grid = {
    description = "GB grid BMRS ingester";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];

    environment = {
      GB_GRID_DATA_DIR = dataDir;
    };

    serviceConfig = {
      User = "gb-grid";
      Group = "gb-grid";
      WorkingDirectory = appHome;
      ExecStart = "${gb-grid-pkg}/bin/gb-grid run";
      Restart = "on-failure";
      RestartSec = "30s";
      NoNewPrivileges = true;
      PrivateTmp = true;
      ProtectSystem = "strict";
      ReadWritePaths = [ appHome ];
    };
  };
}
