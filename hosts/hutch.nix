{ config, pkgs, pkgs-unstable, sops-nix, gb-grid, gb-grid-pkg, lib, ... }:

let
  hostsLib = import ../lib/network.nix { inherit lib; };
  keys = import ../modules/keys.nix;

  # Containers that decrypt secrets/<name>.yaml. The decryption key lives at
  # /var/lib/sops-nix/<name>/ on this host (root-only, NOT in the repo) and
  # is bind-mounted read-only into the container at /var/secrets. The
  # filename differs per container — see each container's sops.age.keyFile.
  withSecrets = [ "caddy" "gb-grid" "immich" "uptime" ];

  # Containers that read the media library from the local ZFS pool. Guarded
  # below so they can't start against an empty dir if the pool didn't import.
  withMediaGuard = [ "immich" "plex" "sonarr" "transmission" ];

  # Per-container extras, merged over the defaults in the containers block.
  perContainer = {
    # The photo library, straight off the local ZFS pool.
    immich.bindMounts."/mnt/media/Photos" = {
      hostPath = "/mnt/Hutch/Media/Photos";
      isReadOnly = false;
    };

    # Read-only — Plex never writes media.
    plex.bindMounts = {
      "/media/Movies" = { hostPath = "/mnt/Hutch/Media/Movies"; isReadOnly = true; };
      "/media/Music"  = { hostPath = "/mnt/Hutch/Media/Music";  isReadOnly = true; };
      "/media/TV"     = { hostPath = "/mnt/Hutch/Media/TV";     isReadOnly = true; };
    };

    # The whole Media dataset, rw, at the path both apps are configured for.
    sonarr.bindMounts."/mnt/media" = {
      hostPath = "/mnt/Hutch/Media";
      isReadOnly = false;
    };
    transmission.bindMounts."/mnt/media" = {
      hostPath = "/mnt/Hutch/Media";
      isReadOnly = false;
    };

    # /dev/net/tun + CAP_NET_ADMIN for tailscaled.
    tailscale.enableTun = true;

    # QSV/hardware transcode for plex + immich. hutch's i5-12600K has a UHD
    # 770 iGPU and /dev/dri/renderD128 is present on the host, so exposing it
    # is just a bind mount + allowedDevices — no passthrough to arrange like
    # the old LXC dev0/dev1 gid mapping.
    #
    # The userspace half (hardware.graphics, intel-media-driver, vpl-gpu-rt,
    # video/render groups) already lives in the two container configs; the
    # host needs no hardware.graphics of its own, since each nspawn guest
    # builds its own /run/opengl-driver. Without these four lines both apps
    # silently transcode on CPU.
    #
    # Verify after deploy with `vainfo` inside each container — it should
    # report the iHD driver and H264/HEVC VLD+encode entrypoints.
    plex.allowedDevices   = [ { node = "/dev/dri/renderD128"; modifier = "rw"; } ];
    plex.bindMounts."/dev/dri"   = { hostPath = "/dev/dri"; isReadOnly = false; };
    immich.allowedDevices = [ { node = "/dev/dri/renderD128"; modifier = "rw"; } ];
    immich.bindMounts."/dev/dri" = { hostPath = "/dev/dri"; isReadOnly = false; };
  };
in
{
  imports = [
    ../modules/locale.nix
    # Host-level secrets. Unlike the containers, hutch decrypts with its own SSH
    # host key (sops.age.sshKeyPaths default) — nothing to place by hand.
    sops-nix.nixosModules.sops
    # NAS role: ZFS pool import, NFS, snapshots, encrypted B2 backup
    ../modules/nas.nix
    # btrfs subvolumes + nightly snapshots for the container roots
    ../modules/container-snapshots.nix
  ];
  # Newest kernel that is both supported by ZFS 2.4.3 (max 7.0) and not
  # EOL-removed in nixpkgs (7.0, 6.19, 6.17 all are; latest is 7.1).
  boot.kernelPackages = pkgs.linuxPackages_6_18;
  networking.hostName = "hutch";

  # systemd-networkd. Topology:
  #
  #   physical NICs ─► bond0 (active-backup) ─► br0 (.2) ◄─ container veths
  #
  # EVERY physical ethernet port is a slave of bond0, matched by Type=ether
  # rather than by name — adding a PCI card can renumber enpXsY, and new
  # ports should just become extra uplink paths. bond0 is br0's single
  # uplink port; br0 owns .2 and the containers attach to it via hostBridge.
  #
  # active-backup means exactly one NIC carries traffic and the rest are hot
  # standbys: whichever cable is plugged in Just Works, failover on link loss
  # is ~100ms (MII monitor), and a switching loop is impossible even with
  # both NICs cabled to the same switch — so NO STP on br0. (STP was tried
  # first and caused LAN-wide instability: the bridge's random low MAC won
  # root-bridge election against the UniFi kit, and every container veth
  # start/stop forced 30s listening/learning plus topology-change FDB
  # flushes — intermittent multi-second blackholes of established TCP.)
  #
  # The bond carries a FIXED MAC (the Supermicro onboard NIC's) so the LAN
  # identity of .2 never changes across boots, failovers, or cable moves.
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
      address = hostsLib.getIP "hutch";
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
          # Fixed LAN identity for .2 (the Supermicro onboard NIC's MAC).
          MACAddress = "0c:c4:7a:bd:45:32";
        };
        bondConfig = {
          Mode = "active-backup";
          MIIMonitorSec = "100ms";
        };
      };
      # Same fixed MAC as the bond: without it the bridge adopts the lowest
      # port MAC, and container veths get random ones — br0's (and so .2's)
      # MAC would change whenever a container with a low MAC starts/stops.
      "40-br0".netdevConfig = {
        Kind = "bridge";
        Name = "br0";
        MACAddress = "0c:c4:7a:bd:45:32";
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

  # NixOS containers, one per network.nix host with `parent = "hutch"`.
  # IPs and bridge derive from lib/network.nix.
  containers = lib.mapAttrs' (name: cfg:
    lib.nameValuePair name (lib.recursiveUpdate {
      privateNetwork = true;
      hostBridge = "br0";
      localAddress = "${cfg.ip}/24";
      autoStart = true;
      # gb-grid/gb-grid-pkg are only consumed by the gb-grid container,
      # sops-nix only by the ones in withSecrets — harmless elsewhere.
      specialArgs = { inherit pkgs-unstable sops-nix gb-grid gb-grid-pkg; };
      config = { imports = [ (./containers + "/${name}.nix") ]; };
      bindMounts = lib.optionalAttrs (builtins.elem name withSecrets) {
        "/var/secrets" = {
          hostPath = "/var/lib/sops-nix/${name}";
          isReadOnly = true;
        };
      };
    } (perContainer.${name} or {}))
  ) (hostsLib.getContainers "hutch");

  # Don't let media containers start against an empty library if the pool
  # didn't import — nspawn would happily bind an empty host dir otherwise.
  systemd.services = lib.genAttrs (map (n: "container@${n}") withMediaGuard) (_: {
    requires = [ "zfs-mount.service" ];
    after = [ "zfs-mount.service" ];
    unitConfig.ConditionPathIsMountPoint = "/mnt/Hutch/Media";
  });

  systemd.tmpfiles.rules =
    map (n: "d /var/lib/sops-nix/${n} 0700 root root -") withSecrets;

  # Boot loader
  boot.loader = {
    systemd-boot.enable = true;
    efi.canTouchEfiVariables = true;
  };

  # SSH + deploy user for deploy-rs
  # Keys only: PasswordAuthentication off, and KbdInteractiveAuthentication
  # off too — with UsePAM the latter would otherwise *advertise* a
  # keyboard-interactive path (blocked only by pam_deny in the sshd PAM
  # stack). Stating both makes keys-only unambiguous.
  services.openssh = {
    enable = true;
    openFirewall = true;
    settings = {
      PermitRootLogin = "no";
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
    };
  };
  users.users.deploy = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    openssh.authorizedKeys.keys = [ keys.chris ];
  };
  # chris: interactive console/SSH login. uid must match the account created
  # on first setup (useradd -u 1001). No password option here on purpose —
  # the one set via chpasswd on the live box survives rebuilds, and keeps the
  # secret out of the repo; add initialHashedPassword if that ever changes.
  users.users.chris = {
    isNormalUser = true;
    uid = 1001;
    extraGroups = [ "wheel" ];
    openssh.authorizedKeys.keys = [ keys.chris ];
  };
  users.users.root.openssh.authorizedKeys.keys = [ keys.chris ];
  security.sudo.wheelNeedsPassword = false;

  # Nix settings
  nix.settings = {
    experimental-features = [ "nix-command" "flakes" ];
    sandbox = false;
    require-sigs = false;
  };

  environment.systemPackages = with pkgs; [
    vim
    htop
    git
  ];

  nixpkgs.config.allowUnfree = true;
  system.stateVersion = "26.05";
}
