{ config, pkgs, sops-nix, gb-grid, lib, ... }:

# GB power grid (Postgres + TimescaleDB + Grafana + BMRS ingester) as a NixOS
# container on hutch — replaces the Proxmox LXC (hosts/lxc/gb-grid.nix).
# The gb-grid flake module and package arrive via the container's specialArgs
# (see hosts/hutch.nix). Same secrets/gb-grid.yaml; the age key is copied
# from the LXC into /var/lib/sops-nix/gb-grid/ on the host (bind-mounted to
# /var/secrets) before cutover. See docs/lxc-migration.md.

let
  dbUser = "gb_grid";
in
{
  imports = [
    ./common.nix
    sops-nix.nixosModules.sops
    gb-grid.nixosModules.default
  ];

  # Postgres + Grafana + ingester all come from the gb-grid flake module.
  services.gb-grid.enable = true;

  networking = {
    hostName = "gb-grid";
    # Module already opens the Grafana port; add Postgres for LAN access.
    firewall.allowedTCPPorts = [ 5432 ];
  };

  # Same age key the LXC keeps at /var/lib/sops-nix/key.txt (the laptop key,
  # copied out of band from 1Password).
  sops = {
    defaultSopsFile = ../../secrets/gb-grid.yaml;
    age.keyFile = "/var/secrets/key.txt";
    secrets.postgres_password = {
      owner = "postgres";
    };
  };

  # Override the module's default pg_hba to require passwords for LAN clients.
  services.postgresql.authentication = lib.mkOverride 10 ''
    local all all                      peer
    host  all all 127.0.0.1/32         trust
    host  all all ::1/128               trust
    host  all ${dbUser} 192.168.1.0/24 scram-sha-256
    host  all ${dbUser} 192.168.4.0/24 scram-sha-256
  '';
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
}
