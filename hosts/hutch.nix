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
    "caddy"
    "gb-grid"
    "immich"
    "pihole-1"
    "pihole-2"
    "plex"
    "sonarr"
    "tailscale"
    "transmission"
    "uptime"
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

  # The primary NIC (Supermicro onboard, MAC 0c:c4:7a:bd:45:32) is bridged
  # into br0 so NixOS containers get LAN-reachable IPs via hostBridge (same
  # L2 as the rest of the 192.168.1.0/24 fleet). The installer environment
  # called this NIC enx0cc47abd4532; the installed system uses the PCI-path
  # name enp1s0 — same card, same MAC.
  #
  # systemd-networkd. enp1s0 is the intended primary uplink (bridged into
  # br0 for the containers) but is NOT cabled yet — enp3s0 is the only real
  # link today and provides IPv4+IPv6 via DHCP/SLAAC.
  #
  # The trap that caused "works on switch, dies on reboot": br0 gets carrier
  # from the container veths even while enp1s0 is dark, so
  # ConfigureWithoutCarrier=false does NOT stop it being configured. With
  # .2 + a metric-100 default route on a bridge that has no physical uplink,
  # IPv4 was blackholed (IPv6 kept flowing out enp3s0's RA route — hence
  # google.com v6 pinging while 1.1.1.1 v4 didn't). Fix: br0's default route
  # carries a HIGH metric (2000, > networkd's DHCP default 1024) so it can
  # never win while enp1s0 is unplugged — enp3s0's DHCP route always carries
  # IPv4. When enp1s0 is eventually cabled and br0/.2 become reachable,
  # promote the metric (< 1024) to make it the true primary again.
  networking = {
    useNetworkd = true;
    bridges.br0.interfaces = [ "enp1s0" ];
    interfaces.br0.ipv4.addresses = [{
      address = hostsLib.getIP "hutch";
      prefixLength = 24;
    }];
    interfaces.enp3s0.useDHCP = true;
    defaultGateway = {
      address = hostsLib.gateway;
      interface = "br0";
      metric = 2000;
    };
    inherit (hostsLib) nameservers;
    firewall.allowedTCPPorts = [ 22 ];
  };

  # networkd gets IPv6 SLAAC/RA explicitly (defaults aren't guaranteed), and
  # br0 must not be configured at all while its port has no carrier.
  systemd.network.networks = {
    "40-br0" = {
      networkConfig.ConfigureWithoutCarrier = false;
      networkConfig.IPv6AcceptRA = true;
    };
    "40-enp3s0" = {
      networkConfig.IPv6AcceptRA = true;
    };
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
