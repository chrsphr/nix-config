{ config, pkgs, lib, gb-grid-pkg, ... }:

let
  hostsLib = import ./hosts.nix { inherit lib; };
  appHome = "/var/lib/gb-grid";
  dbName = "gb_grid";
  dbUser = "gb_grid";
in
{
  imports = [ ./common.nix ];

  networking = hostsLib.mkStaticNetwork "gb-grid" // {
    hostName = "gb-grid";
    firewall.allowedTCPPorts = [ 5432 ];
  };

  # Decrypt sops secrets with the laptop age key copied onto this host
  # (out of band from 1Password) at /var/lib/sops-nix/key.txt.
  sops = {
    defaultSopsFile = ./secrets/gb-grid.yaml;
    age.keyFile = "/var/lib/sops-nix/key.txt";
    secrets.postgres_password = {
      owner = "postgres";
    };
  };

  environment.systemPackages = [
    gb-grid-pkg
    pkgs.postgresql_16
  ];

  users.users.gb_grid = {
    isSystemUser = true;
    group = "gb_grid";
    home = appHome;
    createHome = true;
  };
  users.groups.gb_grid = {};

  systemd.tmpfiles.rules = [
    "d ${appHome} 0750 gb_grid gb_grid -"
  ];

  services.postgresql = {
    enable = true;
    package = pkgs.postgresql_16;
    enableTCPIP = true;
    ensureDatabases = [ dbName ];
    ensureUsers = [{
      name = dbUser;
      ensureDBOwnership = true;
    }];
    authentication = lib.mkOverride 10 ''
      local all all                      peer
      host  all all 127.0.0.1/32         trust
      host  all all ::1/128               trust
      host  all ${dbUser} 192.168.1.0/24 scram-sha-256
      host  all ${dbUser} 192.168.4.0/24 scram-sha-256
    '';
  };

  # Apply the password from sops to the gb_grid role on each boot.
  # Idempotent — rotating the password is just `sops secrets/gb-grid.yaml` + redeploy.
  systemd.services.gb-grid-set-password = {
    description = "Apply gb_grid postgres role password from sops";
    after = [ "postgresql.service" "sops-nix.service" ];
    requires = [ "postgresql.service" ];
    wantedBy = [ "multi-user.target" ];
    path = [ config.services.postgresql.package ];
    serviceConfig = {
      Type = "oneshot";
      User = "postgres";
    };
    script = ''
      pw=$(cat ${config.sops.secrets.postgres_password.path})
      psql -v ON_ERROR_STOP=1 --no-psqlrc -d postgres <<SQL
      ALTER ROLE ${dbUser} WITH LOGIN PASSWORD '$pw';
      SQL
    '';
  };

  systemd.services.gb-grid = {
    description = "GB grid BMRS ingester";
    after = [ "network-online.target" "postgresql.service" ];
    requires = [ "postgresql.service" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];

    environment = {
      # App connects via the local socket as the gb_grid OS user (peer auth).
      GB_GRID_DATABASE_URL = "postgresql:///${dbName}";
    };

    serviceConfig = {
      User = dbUser;
      Group = dbUser;
      WorkingDirectory = appHome;
      ExecStartPre = "${gb-grid-pkg}/bin/gb-grid migrate";
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
