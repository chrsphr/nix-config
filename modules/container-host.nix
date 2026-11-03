{ config, pkgs, pkgs-unstable, sops-nix, gb-grid, gb-grid-pkg, lib, ... }:

# The container-host role: LAN bond/bridge plus every NixOS container that
# lib/network.nix names this machine as `parent` of (see README). Per-host
# knobs live under `containerHost.*`; anything machine-specific stays in
# hosts/<name>.nix.

let
  hostsLib = import ../lib/network.nix { inherit lib; };
  cfg = config.containerHost;
  hostName = config.networking.hostName;
  hostContainers = hostsLib.getContainers hostName;

  # Containers with a `vlan` field get their own tagged bridge instead of
  # br0: bond0.<id> (VLAN tag) -> br<id> (untagged container side).
  vlanIds = lib.unique (
    map (c: c.vlan)
      (builtins.filter (c: c ? vlan) (builtins.attrValues hostContainers))
  );
  vlanNetdevs = lib.listToAttrs (map (vlan: {
    name = "25-bond0.${toString vlan}";
    value = {
      netdevConfig = { Kind = "vlan"; Name = "bond0.${toString vlan}"; };
      vlanConfig.Id = vlan;
    };
  }) vlanIds);
  vlanBridges = lib.listToAttrs (map (vlan: {
    name = "45-br${toString vlan}";
    value.netdevConfig = { Kind = "bridge"; Name = "br${toString vlan}"; };
  }) vlanIds);
  vlanNetworks = lib.listToAttrs (map (vlan: {
    name = "25-bond0.${toString vlan}";
    value = {
      matchConfig.Name = "bond0.${toString vlan}";
      networkConfig.Bridge = "br${toString vlan}";
    };
  }) vlanIds);
  vlanBridgeNetworks = lib.listToAttrs (map (vlan: {
    name = "45-br${toString vlan}";
    value = {
      matchConfig.Name = "br${toString vlan}";
      # The UniFi gateway routes this VLAN; the host is unnumbered on it.
      networkConfig.LinkLocalAddressing = "no";
    };
  }) vlanIds);
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
      } // vlanNetdevs // vlanBridges;
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
        # The bond is the bridge's uplink port. VLAN children are listed here
        # explicitly; without the parent reference networkd does not create
        # the stacked VLAN netdev.
        "30-bond0" = {
          matchConfig.Name = "bond0";
          networkConfig = {
            Bridge = "br0";
            VLAN = map (vlan: "bond0.${toString vlan}") vlanIds;
          };
        };
        # networkd gets IPv6 SLAAC/RA explicitly (defaults aren't guaranteed).
        "40-br0".networkConfig.IPv6AcceptRA = true;
      } // vlanNetworks // vlanBridgeNetworks;
    };

    # NixOS containers, one per lib/network.nix host with `parent = <this host>`.
    # IPs and bridge derive from lib/network.nix.
    containers = lib.mapAttrs' (name: hostCfg:
      let
        isStatic = hostCfg ? ip;
        extra = cfg.perContainer.${name} or {};
      in lib.nameValuePair name (lib.recursiveUpdate ({
        privateNetwork = true;
        hostBridge =
          if (hostCfg.vlan or null) != null
          then "br${toString hostCfg.vlan}"
          else "br0";
        # nspawn picks a random MAC per start; pin a deterministic one so the
        # container's LAN identity and DHCP lease stay stable across restarts.
        localMacAddress = hostsLib.getMAC name;
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
      } // (if isStatic then {
        localAddress = "${hostCfg.ip}/${toString (hostCfg.prefixLength or 24)}";
      } else {
        # dhcpcd inside the container needs CAP_NET_ADMIN to configure eth0.
        # (enableTun also adds CAP_NET_ADMIN in nixos-containers.nix; skip
        # duplicating it when enableTun is set.)
        additionalCapabilities =
          lib.optional (!(extra.enableTun or false)) "CAP_NET_ADMIN";
      })) extra)
    ) hostContainers;

    # Stop/start race hardening, learned from a rolled-back deploy: a busy
    # container (plex mid-encode) can blow the default 90s stop timeout, the
    # resulting SIGKILL leaks /run/systemd/nspawn/unix-export/<name>, and the
    # immediate restart then fails with "Mount point exists already,
    # refusing" — which fails switch-to-configuration and rolls back the whole
    # deploy. So: allow 3min before the SIGKILL, and remove any stale
    # unix-export dir before each start (%i = container name).
    # Also remove any stale veth (ve-%i / vb-%i): nixos-containers.nix's
    # preStart only deletes them when localAddress != null.
    # why: docs/notes.md#nspawn-stop-race
    systemd.services = (lib.genAttrs
      (map (n: "container@${n}") (builtins.attrNames hostContainers))
      (_: {
        serviceConfig = {
          TimeoutStopSec = "3min";
          ExecStartPre = [
            "-${pkgs.coreutils}/bin/rm -rf /run/systemd/nspawn/unix-export/%i"
            "-${pkgs.iproute2}/bin/ip link del dev ve-%i"
            "-${pkgs.iproute2}/bin/ip link del dev vb-%i"
          ];
        };
      })) // {
      # systemd-journal-upload exits on the first DNS/connection failure. Run
      # it in a retry loop so the unit stays `active` for
      # switch-to-configuration, and an unresolvable prometheus.internal can
      # never become a tight restart loop that floods the Pi-holes with
      # thousands of queries/s until they rate-limit the UDM (which blackholes
      # LAN DNS). 5s between attempts is plenty for a log shipper.
      # why: docs/notes.md#prometheus-and-journal-remote
      systemd-journal-upload = {
        unitConfig.StartLimitIntervalSec = 0;
        serviceConfig = {
          # The empty entry resets the upstream ExecStart list in the drop-in;
          # without it systemd sees two ExecStart= lines and rejects the unit.
          ExecStart = lib.mkForce [
            ""
            (toString (pkgs.writeShellScript "journal-upload-retry" ''
              while true; do
                ${config.systemd.package}/lib/systemd/systemd-journal-upload --save-state || true
                sleep 5
              done
            ''))
          ];
          RestartSec = lib.mkForce "1s";
        };
      };
    };

    # Host telemetry + journal shipping to the prometheus container.
    # why: docs/notes.md#prometheus-and-journal-remote
    services.prometheus.exporters = {
      node = {
        enable = true;
        openFirewall = true;
        enabledCollectors = [ "systemd" ];
      };
      smartctl = {
        enable = true;
        openFirewall = true;
      };
    };
    services.journald.upload = {
      enable = true;
      settings.Upload.URL = "http://${hostsLib.getIP "prometheus"}:19532";
    };

    systemd.tmpfiles.rules =
      map (n: "d /var/lib/sops-nix/${n} 0700 root root -") cfg.withSecrets;
  };
}
