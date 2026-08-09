{ config, pkgs, pkgs-unstable, sops-nix, gb-grid, gb-grid-pkg, lib, ... }:

# The container-host role: LAN bond/bridge plus every NixOS container that
# lib/network.nix says belongs to this machine.
#
# Imported by hutch and minihutch. Everything here is derived from
# `networking.hostName` and lib/network.nix, so a host that imports this
# module declares containers purely by being named as some host's `parent`.
#
# Per-host knobs live under `containerHost.*` (see the options block below);
# anything genuinely specific to one machine — the NAS role, media bind
# mounts, iGPU passthrough — stays in that machine's hosts/<name>.nix.

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
    # systemd-networkd. Topology:
    #
    #   physical NICs ─► bond0 (active-backup) ─► br0 (host IP) ◄─ container veths
    #
    # EVERY physical ethernet port is a slave of bond0, matched by Type=ether
    # rather than by name — adding a PCI card can renumber enpXsY, and new
    # ports should just become extra uplink paths. bond0 is br0's single
    # uplink port; br0 owns the host IP and the containers attach to it via
    # hostBridge.
    #
    # active-backup means exactly one NIC carries traffic and the rest are hot
    # standbys: whichever cable is plugged in Just Works, failover on link loss
    # is ~100ms (MII monitor), and a switching loop is impossible even with
    # both NICs cabled to the same switch — so NO STP on br0. (STP was tried
    # first on hutch and caused LAN-wide instability: the bridge's random low
    # MAC won root-bridge election against the UniFi kit, and every container
    # veth start/stop forced 30s listening/learning plus topology-change FDB
    # flushes — intermittent multi-second blackholes of established TCP.)
    #
    # If a future NIC must NOT be an uplink (dedicated 10G to another box,
    # say), give it its own systemd.network.networks unit sorting before
    # "20-lan-port" with a narrower match — first match wins.
    #
    # History, so this doesn't get "fixed" back: br0 previously held .2 while its
    # only port (enp1s0) was unplugged, with enp3s0 separately holding a DHCP .124.
    # br0 still came up (container veths give the bridge carrier, so
    # ConfigureWithoutCarrier=false does not stop it), and its connected
    # 192.168.1.0/24 route at metric 0 beat enp3s0's DHCP route at metric 1024 —
    # so every packet to the LAN, including SSH replies arriving on enp3s0, was
    # routed into a bridge with no cable and dropped. Raising the *default* route
    # metric to 2000 never helped, because LAN traffic uses the connected route.
    # The arp_ignore/arp_filter sysctls that followed were treating symptoms of
    # that blackhole (and arp_filter additionally stopped .124 answering ARP at
    # all, since the route lookup for the sender kept returning br0). One
    # L3 identity on the subnet makes all of it unnecessary.
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
        # networking.bridges/bonds are not used — they want fixed port-name
        # lists, defeating the catch-all port match below.
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
        # Same fixed MAC as the bond: without it the bridge adopts the lowest
        # port MAC, and container veths get random ones — br0's (and so the
        # host IP's) MAC would change whenever a container with a low MAC
        # starts/stops.
        "40-br0".netdevConfig = {
          Kind = "bridge";
          Name = "br0";
        } // lib.optionalAttrs (cfg.macAddress != null) {
          MACAddress = cfg.macAddress;
        };
      };
      networks = {
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

    systemd.tmpfiles.rules =
      map (n: "d /var/lib/sops-nix/${n} 0700 root root -") cfg.withSecrets;
  };
}
