{ config, pkgs, pkgs-unstable, sops-nix, gb-grid, gb-grid-pkg, lib, ... }:

# The container-host role: LAN bond/bridge plus every NixOS container that
# lib/network.nix names this machine as `parent` of (see README). Per-host
# knobs live under `containerHost.*`; anything machine-specific stays in
# hosts/<name>.nix.

let
  hostsLib = import ../lib/network.nix { inherit lib; };
  cfg = config.containerHost;
  hostName = config.networking.hostName;
in
{
  imports = [
    # btrfs subvolumes + nightly snapshots for the container roots
    ./container-snapshots.nix
  ];

  options.containerHost = {
    enable = lib.mkEnableOption "the LAN bridge + NixOS container host role";

    macAddress = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "0c:c4:7a:bd:45:32";
      description = ''
        Fixed MAC for bond0 and br0, normally the onboard NIC's, so this
        machine's LAN identity never changes across boots, failovers or cable
        moves. null lets the bond adopt whichever port MAC it likes — which
        also means br0 can inherit a *container veth's* random MAC when a
        container starts, so prefer setting it.
      '';
    };

    withSecrets = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      example = [ "caddy" "uptime" ];
      description = ''
        Containers that decrypt secrets/<name>.yaml. The decryption key lives
        at /var/lib/sops-nix/<name>/ on this host (root-only, NOT in the repo)
        and is bind-mounted read-only into the container at /var/secrets. The
        filename differs per container — see each container's sops.age.keyFile.
      '';
    };

    excludePorts = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      example = [ "enp2s0" ];
      description = ''
        Physical ports to keep OUT of bond0, held administratively down.

        An unpopulated onboard port left in the bond is not free: the bond
        MII-polls it every 100ms and its PHY keeps retrying autonegotiation,
        which holds the port's PCIe root port out of L1 and pins the package
        to PC3. It also buys no redundancy while no cable is in it.
        why: docs/notes.md#aspm-package-cstates
      '';
    };

    perContainer = lib.mkOption {
      type = lib.types.attrsOf lib.types.anything;
      default = {};
      description = ''
        Per-container extras (bind mounts, allowedDevices, enableTun, …),
        merged with lib.recursiveUpdate over the defaults below.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    # physical NICs ─► bond0 (active-backup) ─► br0 (host IP) ◄─ container veths
    # NO STP on br0 — do not "fix" this back.
    # why: docs/notes.md#bond0-to-br0, #no-stp; history: docs/notes.md#br0-blackhole
    networking = {
      useNetworkd = true;
      interfaces.br0.ipv4.addresses = [{
        address = hostsLib.getIP hostName;
        prefixLength = 24;
      }];
      defaultGateway = {
        address = hostsLib.gateway;
        interface = "br0";
      };
      inherit (hostsLib) nameservers;
      firewall.allowedTCPPorts = [ 22 ];
    };

    systemd.network = {
      netdevs = {
        "20-bond0" = {
          netdevConfig = {
            Kind = "bond";
            Name = "bond0";
          } // lib.optionalAttrs (cfg.macAddress != null) {
            MACAddress = cfg.macAddress;
          };
          bondConfig = {
            Mode = "active-backup";
            MIIMonitorSec = "100ms";
          };
        };
        # Same fixed MAC as the bond. why: docs/notes.md#fixed-bridge-mac
        "40-br0".netdevConfig = {
          Kind = "bridge";
          Name = "br0";
        } // lib.optionalAttrs (cfg.macAddress != null) {
          MACAddress = cfg.macAddress;
        };
      };
      networks = lib.optionalAttrs (cfg.excludePorts != []) {
        # Sorts before the 20-lan-port catch-all, so these ports never reach
        # the bond. always-down keeps the PHY from autonegotiating at all.
        "10-lan-port-excluded" = {
          matchConfig.Name = lib.concatStringsSep " " cfg.excludePorts;
          linkConfig.ActivationPolicy = "always-down";
        };
      } // {
        # Catch-all: every physical ethernet port becomes a bond slave. Sorts
        # before the stock 99-ethernet-default-dhcp catch-all, so it wins for
        # physical NICs; bond0/br0/veths all have a Kind, so Kind=!* skips them.
        "20-lan-port" = {
          matchConfig = { Type = "ether"; Kind = "!*"; };
          networkConfig.Bond = "bond0";
        };
        # The bond is the bridge's uplink port.
        "30-bond0" = {
          matchConfig.Name = "bond0";
          networkConfig.Bridge = "br0";
        };
        # networkd gets IPv6 SLAAC/RA explicitly (defaults aren't guaranteed).
        "40-br0".networkConfig.IPv6AcceptRA = true;
      };
    };

    # NixOS containers, one per lib/network.nix host with `parent = <this host>`.
    # IPs and bridge derive from lib/network.nix.
    containers = lib.mapAttrs' (name: hostCfg:
      lib.nameValuePair name (lib.recursiveUpdate {
        privateNetwork = true;
        hostBridge = "br0";
        localAddress = "${hostCfg.ip}/24";
        autoStart = true;
        # gb-grid/gb-grid-pkg are only consumed by the gb-grid container,
        # sops-nix only by the ones in withSecrets — harmless elsewhere.
        specialArgs = { inherit pkgs-unstable sops-nix gb-grid gb-grid-pkg; };
        config = { imports = [ (../hosts/containers + "/${name}.nix") ]; };
        bindMounts = lib.optionalAttrs (builtins.elem name cfg.withSecrets) {
          "/var/secrets" = {
            hostPath = "/var/lib/sops-nix/${name}";
            isReadOnly = true;
          };
        };
      } (cfg.perContainer.${name} or {}))
    ) (hostsLib.getContainers hostName);

    # Stop/start race hardening, learned from a rolled-back deploy: a busy
    # container (plex mid-encode) can blow the default 90s stop timeout, the
    # resulting SIGKILL leaks /run/systemd/nspawn/unix-export/<name>, and the
    # immediate restart then fails with "Mount point exists already,
    # refusing" — which fails switch-to-configuration and rolls back the whole
    # deploy. So: allow 3min before the SIGKILL, and remove any stale
    # unix-export dir before each start (%i = container name).
    # why: docs/notes.md#nspawn-stop-race
    systemd.services = lib.genAttrs
      (map (n: "container@${n}") (builtins.attrNames (hostsLib.getContainers hostName)))
      (_: {
        serviceConfig = {
          TimeoutStopSec = "3min";
          ExecStartPre = [
            "-${pkgs.coreutils}/bin/rm -rf /run/systemd/nspawn/unix-export/%i"
          ];
        };
      });

    systemd.tmpfiles.rules =
      map (n: "d /var/lib/sops-nix/${n} 0700 root root -") cfg.withSecrets;
  };
}
