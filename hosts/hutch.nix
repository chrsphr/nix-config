{ config, pkgs, pkgs-unstable, sops-nix, gb-grid, gb-grid-pkg, lib, ... }:

let
  hostsLib = import ../lib/network.nix { inherit lib; };
  keys = import ../modules/keys.nix;

  # Containers replacing live Proxmox LXCs share the LXC's IP, so they must
  # not start until that service is cut over (shut down the LXC, remove the
  # name from this list, deploy). Test containers (unique IPs) start
  # immediately. See docs/lxc-migration.md.
  cutoverPending = [
    "beeper"
    "gb-grid"
    "immich"
    "pihole-2"
    "plex"
    "sonarr"
    "tailscale"
    "transmission"
  ];

  # Containers that decrypt the same secrets/<name>.yaml as their LXC. The
  # decryption key (age key or SSH host key, depending on the service) is
  # copied from the LXC into /var/lib/sops-nix/<name>/ on this host and
  # bind-mounted into the container at /var/secrets.
  withSecrets = [ "caddy" "gb-grid" "immich" "uptime" ];

  # Containers that read the media library from the local ZFS pool. Guarded
  # below so they can't start against an empty dir if the pool didn't import.
  withMediaGuard = [ "immich" "plex" "sonarr" "transmission" ];

  # Per-container extras, merged over the defaults in the containers block.
  perContainer = {
    # The photo library lives on the local ZFS pool — bind it straight in
    # instead of the NFS loopback the LXC used (Proxmox host mounted
    # 192.168.1.12:/mnt/Hutch/Media over NFS, then bind-mounted that).
    immich.bindMounts."/mnt/media/Photos" = {
      hostPath = "/mnt/Hutch/Media/Photos";
      isReadOnly = false;
    };

    # The LXC got the library as read-only binds at /media/{Movies,Music,TV}
    # (Plex never writes media). Same internal paths here.
    plex.bindMounts = {
      "/media/Movies" = { hostPath = "/mnt/Hutch/Media/Movies"; isReadOnly = true; };
      "/media/Music"  = { hostPath = "/mnt/Hutch/Media/Music";  isReadOnly = true; };
      "/media/TV"     = { hostPath = "/mnt/Hutch/Media/TV";     isReadOnly = true; };
    };

    # The LXCs NFS-mounted the whole Media share rw at /mnt/media — keep the
    # same internal path against the local dataset.
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

    # QSV/hardware transcode for plex + immich: on baremetal there is no
    # passthrough to arrange — if hutch's CPU has an Intel iGPU, /dev/dri is
    # already on the host. Uncomment to expose it to the containers:
    # plex.allowedDevices   = [ { node = "/dev/dri"; modifier = "rw"; } ];
    # plex.bindMounts."/dev/dri"   = { hostPath = "/dev/dri"; isReadOnly = false; };
    # immich.allowedDevices = [ { node = "/dev/dri"; modifier = "rw"; } ];
    # immich.bindMounts."/dev/dri" = { hostPath = "/dev/dri"; isReadOnly = false; };
  };
in
{
  imports = [
    ../modules/locale.nix
    # NAS role: ZFS pool import, NFS, snapshots, B2 sync (TrueNAS replacement)
    ../modules/nas.nix
    # btrfs subvolumes + nightly snapshots for the container roots
    ../modules/container-snapshots.nix
  ];

  networking.hostName = "hutch";

  # systemd-networkd. EVERY physical ethernet port is a port of br0 (matched
  # by Type=ether, not by name — adding a PCI card can renumber enpXsY, and
  # new ports should just become extra uplinks), and br0 is the only thing on
  # the LAN: it owns .2, and the containers attach to it via hostBridge. A
  # bridge port with no carrier is inert, so whichever cable is plugged in
  # Just Works — today that's the PCIe NIC (enp3s0); at rack time the cable
  # moves to the Supermicro onboard port (enp1s0, MAC 0c:c4:7a:bd:45:32) with
  # no config change. STP is on so that having two ports cabled to the same
  # switch forms no loop (one goes into blocking); it also means a fresh link
  # waits a few seconds in listening/learning before forwarding.
  #
  # If a future NIC must NOT be a bridge port (dedicated 10G to another box,
  # say), give it its own systemd.network.networks unit sorting before
  # "30-lan-port" with a narrower match — first match wins.
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
    interfaces.br0 = {
      ipv4.addresses = [{
        address = hostsLib.getIP "hutch";
        prefixLength = 24;
      }];
      # Belt and braces during the cutover: br0 inherits the DHCP path too, so
      # the box stays reachable on its old lease if .2 is ever wrong. Drop once
      # .2 is proven.
      useDHCP = true;
    };
    defaultGateway = {
      address = hostsLib.gateway;
      interface = "br0";
    };
    inherit (hostsLib) nameservers;
    firewall.allowedTCPPorts = [ 22 ];
  };

  systemd.network = {
    # The bridge device itself (networking.bridges is not used — it would
    # want a fixed port-name list, defeating the catch-all below).
    netdevs."40-br0" = {
      netdevConfig = { Kind = "bridge"; Name = "br0"; };
      bridgeConfig.STP = true;
    };
    # Catch-all: every physical ethernet port joins br0. Sorts before the
    # stock 99-ethernet-default-dhcp catch-all, so it wins for physical NICs;
    # container veths are Kind=veth so neither unit touches them.
    networks."30-lan-port" = {
      matchConfig = { Type = "ether"; Kind = "!*"; };
      networkConfig.Bridge = "br0";
    };
    # networkd gets IPv6 SLAAC/RA explicitly (defaults aren't guaranteed).
    networks."40-br0".networkConfig.IPv6AcceptRA = true;
  };

  # NixOS containers, one per network.nix host with `parent = "hutch"`.
  # IPs and bridge derive from lib/network.nix; autostart is gated by the
  # cutoverPending list above.
  containers = lib.mapAttrs' (name: cfg:
    lib.nameValuePair name (lib.recursiveUpdate {
      privateNetwork = true;
      hostBridge = "br0";
      localAddress = "${cfg.ip}/24";
      autoStart = !(builtins.elem name cutoverPending);
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
